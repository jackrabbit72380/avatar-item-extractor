@echo off
setlocal EnableExtensions
title Avatar Item Extractor v20

rem ===========================================================================
rem  Avatar Item Extractor v20  -  one click
rem
rem  Double-click this file. It unpacks the code it carries to
rem  %LOCALAPPDATA%\AvatarItemExtractor, reads the avatar items sitting in this
rem  file's own folder, and extracts them next to this file. It looks nowhere
rem  else - not Downloads, not Desktop, not Documents.
rem
rem  It needs Python 3.8 or newer and nothing else: the extractor, both
rem  reader modules and the rigging pass all travel inside this file.
rem
rem  It also rigs every item, when it can: put Halo's two rig files in a
rem  folder called rig beside this file
rem      rig\master chief skeleton.blend
rem      rig\fp arms.blend
rem  and have Blender 4.x installed. Without those it extracts and says so.
rem
rem  No folder picker, no drag and drop, no questions.
rem ===========================================================================

set "CACHE=%LOCALAPPDATA%\AvatarItemExtractor"
set "BOOT=%CACHE%\unpack_v20.py"
set "OUT=%~dp0extracted"

echo.
echo   Avatar Item Extractor v20
echo   -------------------------
echo.

if not exist "%CACHE%" mkdir "%CACHE%" >nul 2>&1
echo   Unpacking the code carried inside this file...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0'); $a='###BOOTSTRAP###'; $b='###PAYLOAD###'; $i=$t.LastIndexOf($a); $j=$t.LastIndexOf($b); if($i -lt 0 -or $j -le $i){exit 1}; $s=$t.Substring($i+$a.Length,$j-$i-$a.Length).TrimStart([char]13,[char]10).TrimEnd([char]13,[char]10); $e=New-Object Text.UTF8Encoding($false); [IO.File]::WriteAllText('%BOOT%',$s,$e)"
if not exist "%BOOT%" goto :unpackfailed
echo.

set "PY="
py -3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=py -3"
if defined PY goto :run

python -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python"
if defined PY goto :run

python3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python3"
if defined PY goto :run

echo   Python 3.8 or newer was not found on this computer.
echo.
echo   Install it from https://www.python.org/downloads/windows/
echo   and tick "Add python.exe to PATH" in the installer, then run this
echo   file again. Nothing else is needed.
echo.
start "" https://www.python.org/downloads/windows/
pause
exit /b 2

:run
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto :done
if "%RC%"=="3" goto :unparsed
if "%RC%"=="4" goto :nothing
if "%RC%"=="5" goto :noreaders

echo.
echo   The extractor stopped with code %RC%.
echo   Nothing was deleted or moved. Run this file again to retry.
echo.
pause
exit /b %RC%

:noreaders
echo.
pause
exit /b 5

:nothing
echo.
echo   No item sources were found.
echo.
echo   A source is a closet_index.tsv, or item .bin / .asset files. This file
echo   looked only in its own folder. Put the items there and run it again.
echo.
pause
exit /b 4

:unparsed
echo.
echo   Error: this container does not contain Avatar Item Content.
echo   Please try another.
echo.
echo   The files found are listed above, one line per item, with the reason
echo   each one was not an avatar item.
echo.
pause
exit /b 3

:unpackfailed
echo.
echo   Could not unpack the code carried inside this file.
echo   The file was probably truncated while downloading.
echo.
echo   Download it again, or copy it to C:\Tools and run it from there.
echo.
pause
exit /b 1

:done
echo.
echo   Done. Everything is in:
echo      %OUT%
echo.
pause
endlocal
exit /b 0
###BOOTSTRAP###
"""Unpack the code carried in the .bat, extract the items, then rig them.

Everything the tool needs travels inside the .bat: the extractor, the two
reader modules and the rigging pass. Two things cannot travel with it - Halo's
own rig files and Blender itself - so if a folder called rig holds the two
.blend files and Blender 4.x is installed, the same double-click also rigs
every item; if either is missing the run stops after extracting and says why.
"""

import base64
import glob
import json
import os
import shutil
import subprocess
import sys
import zlib

MARKER = "###PAYLOAD###"
READERS = ("avatar_mesh.py", "lzx.py")
RIGS = ("master chief skeleton.blend", "fp arms.blend")


def ensure_readers(cache, bat_dir):
    """Get avatar_mesh.py and lzx.py into the cache folder, or explain what to do."""
    missing = [name for name in READERS if not os.path.exists(os.path.join(cache, name))]
    for name in missing:
        for folder in (bat_dir, os.getcwd()):
            source = os.path.join(folder, name)
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(cache, name))
                break
    still = [name for name in READERS if not os.path.exists(os.path.join(cache, name))]
    if still:
        print("")
        print("   The reader modules %s are missing." % " and ".join(still))
        print("")
        print("   Copy avatar_mesh.py and lzx.py into the same folder as this")
        print("   file, then run it again. They are needed once: after that the")
        print("   tool keeps its own copy in")
        print("      %s" % cache)
        print("")
        return 5
    return 0


def find_blender():
    """Blender 4.x, from PATH or from its usual Windows install folder."""
    found = shutil.which("blender")
    if found:
        return found
    for root in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if not root:
            continue
        pattern = os.path.join(root, "Blender Foundation", "*", "blender.exe")
        for path in sorted(glob.glob(pattern), reverse=True):
            return path
    return None


def rig(cache, bat_dir, out, inside=False):
    """One rigging pass over everything that was just extracted."""
    rig_dir = os.path.join(bat_dir, "rig")
    blends = [os.path.join(rig_dir, name) for name in RIGS]
    missing = [name for name, path in zip(RIGS, blends) if not os.path.exists(path)]
    if missing:
        print("")
        print("   No rigging: %s not found in %s" % (", ".join(missing), rig_dir))
        print("   Put Halo's two rig files there and run this file again.")
        return 0
    blender = find_blender()
    if not blender:
        print("")
        print("   No rigging: Blender was not found.")
        print("   Install it from https://www.blender.org/download/ and run this")
        print("   file again - it rigs every item without any other setup.")
        return 0
    # Inside the item's own folder when the extraction made one, so a single
    # item keeps everything together; beside the .bat otherwise.
    target = os.path.join(out, "rigged") if inside else os.path.join(bat_dir, "rigged")
    print("")
    print("   Rigging every item onto the Halo skeleton and first-person arms...")
    status = subprocess.call([blender, "-b", "--factory-startup", "--python",
                              os.path.join(cache, "rig_items.py"), "--",
                              "--items", out, "--rig", blends[0],
                              "--fp", blends[1], "--out", target])
    if status:
        print("")
        print("   The rigging pass stopped with code %d." % status)
        print("   The extracted files are fine and are in %s" % out)
        return 0
    print("")
    print("   Rigged files are in %s" % target)
    return 0


def main():
    bat, cache = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    bat_dir = os.path.dirname(os.path.abspath(bat))
    with open(bat, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    blob = "".join(text[text.rfind(MARKER) + len(MARKER):].split())
    files = json.loads(zlib.decompress(base64.b85decode(blob.encode("ascii"))).decode("utf-8"))
    os.makedirs(cache, exist_ok=True)
    for name in sorted(files):
        data = files[name].encode("utf-8")
        path = os.path.join(cache, name)
        if not os.path.exists(path) or open(path, "rb").read() != data:
            with open(path, "wb") as handle:
                handle.write(data)
    status = ensure_readers(cache, bat_dir)
    if status:
        return status
    target = os.path.join(cache, "extract_items.py")
    with open(target, "r", encoding="utf-8") as handle:
        code = compile(handle.read(), target, "exec")
    sys.path.insert(0, cache)
    # The .bat cannot hand its own path over reliably: a trailing backslash
    # escapes the closing quote, so --root arrives as "...folder\". Take the
    # folder from the batch file's real path instead.
    sys.argv = [target, "--root", bat_dir] + rest
    # The extractor records where it actually wrote, which is not the folder it
    # was given when the single item's title named it instead.
    state = {}
    try:
        exec(code, {"__name__": "__main__", "__file__": target, "__state__": state})
        result = 0
    except SystemExit as exc:
        result = exc.code if isinstance(exc.code, int) else 0
    out = "extracted"
    for index, word in enumerate(rest):
        if word == "--out" and index + 1 < len(rest):
            out = rest[index + 1]
    asked = out
    out = state.get("out") or out
    if result == 0:
        rig(cache, bat_dir, out, inside=os.path.abspath(out) != os.path.abspath(asked))
    return result


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-riJi+0;avf!^^l=TFNNSdT%Sz#>im2ElE9lwsHWRgp98IS}e*d)LqKuL5a_uID~{YHbN6VII8v
+F1l3G}nNy1J^m9>49yw{aOShx4SkX)V@!y}hsg@^DowACA)OVUpbji*<REX9ri=)gJ!$A{pnCB;
Z=X96ryAAYYY1J`GOk;b~DM<-2(Nu~p{dAkE4=c>C->ThKsud6O0a{FFCIFi(pj&8~x4ntcqW`H~
(Uya;a7<gQ0w7SKjel=(6#f+QZ_1TnS@zk~QH`z5&i{{6#?%lFTMah{cNnkCEN?j|pi;57~^7|n9
19;TDvAi_T5V0;6maGbCH>*wY;pD&={BAHxeRI~_g^4SDO6bGZUY+~=pBp|p1Z}Rd6U)?0j1o~Ue
Cc!8Pu2<ARaJA~TJBLA9!aQcP{EjAgmBFOuaT%oZ#Vna8SqUXaYXPL-bhV6waJ-Dmq<F~CY;uL70
WB5DYzhNe<V%F?Rd%0bY5a8&d`y;EGJAL*&qbvoY6N#_c|#C`i3Jl{pd|o4n0>m3B_+rQ@K3B{V6
S-4q^Sl^JgfH<UNX>M$Ft;FKEcxY=tD4vuPyk1O+U}GX}X-l?BZ(xa8c4wikoz?fM?it&lniY4qw
y4nG3amso={vg9TB&t<z*SDS}St;Bj!9EX#BZxbQIOc8?B&a+${2^$Z?_FO#{f(diy^vBcq{!-!`
7E-%tD&9eg5ZJrRS0%)F{zj+Z9Fu0@<WH}=h;2QLf%REi5SIeZQXFX5i0-h9CS*P{*+aR9hQ0hJi
R|^1tr}d~K9<3Wey9HzAZ=Yy7!6^QSjRJaHr?)WNJWBw3vJy~#KDx>P1puu8DshIW2i>)TO8^nWW
gIV;DO6e{%O*k~xrY}Cw3@<D5gORTU6NkkAmSAHRfgbIu!;d+7kR;`N9*!2nI&bO1tBc~ck(C-08
uB)_%0~ZdD03H3+AI4?S`vN!A0zP9B%^1ngm&r!1Aaz_u*rjWl$85@+O5X3mXr?YwUrm3~PT!TRs
+JBQg?{`6LDaCijH((`7!lHj4mdf{-d{Y5%@V%QDG=+jzFpa}}$N#U+X;VCC6tjk_84*^Dd9;u0Z
sm5Ke1)qebm-`&Kp38%9h_9Vg|o<s3<vV_4yH9+y0pu#}Nk`&?6l7tcm2-C)?#LH_!Z}s3qk?Xg4
p*|Mnay2gX*L7jE0=pT%U7Uaa=JfK%_h-Y4^Zz;vPJ;G*=dgX1J$v=``QL^=oSnWndoN#gx&S1=^
tXT4g^%0qHnzj%-<-ZayMX7vF^OpRf~&pr3;>!=uJ#)Iu!9dzVHhz&Rz2?G<ICi}gpHvd9^gaT*X
q$BKDxMx7s*>d%Vi2QK)riJ?*#g&r$^Kw(w)~y8BYKOe$1e10lg=BSdX#P^A#Kr^XK_2UtY$rG1S
}RN*g~}E&Pr!xXQ*epl`U(k@hB&@a%q^EO44pPY_Lb&qcoi+V|)F;kklqoWyh8_p`LTphu!Z#-3L
f&zeA0ftX?)c#R}I2Oz*cE{RU^DJpiPI5~jEPT?Q~Qq$5%h>gPYU^q;(v>XmYJX;z8f<#Ud|KZaX
J_KyQKhB$cI>mDUFvxjPq@R)@46=ZCK$t>mH~1zvHv1mmB;${w<7_pj@@D7h)aqql6$+j@y%?47-
!e||#8>NgwTJLRKrL4p614}DAl!#vaO^*rL|1#kgCI1z(!*&u9Yv8j0bGI2<2Ocpbhvet*dCnQ6G
`~tJj2RYdyxZPhMekCzlGCiHFFo_CY?Hu)Vdjy)^BGCm6y%y7eKv%Y|`teKo#uiKvBS@Az~s_7Ck
(`6*o(jNUKkP&&$H&plMcWP{Wa3d>$7cp?KH{o;;zt5mf5fWr)zrxgetTMdweS1_uNDZS>+S0fXz
G&;#}KS8goA-Uw`Vafamn35~>lML=o#-bn0q-&v^bgZ453BASUYx@b3C9aC|MelFg@0v&I~x7Bgr
qTF#6<HR^<yoB*tR2@y{h(=-#qf)PP<f(Yj-CpsaTdkOSD&9&g(6yX4ZvlN6ncyt~>K4{qJm^FLh
%LY-Rr@+RtOd5+XBIijfSiNwBg_zeqsUpATf`hHkX1)q8O?M9$cR;Ft%z@d1%5JxV@*Dl&(7(Y38
pCOw+CiF@#Hqn#))sfCjE)(vDs>EmR@JWG9PBZ7tk)OjNd*@LYwSAjsSrF{n$H(cJ#&0;UWRXa0Z
lqS?GiKr(_JW=7oA?pU2E5Hvh4Tvl8A;usAR~qqsn(6QtY*2#5Fab)LmDScYWLAeKG82M!pIB-nW
6O|ku0X7->0FzR=>1cq~k2Q8OsDI{^12ZuGh-?iX+*MgsRDF~AR2^mJ~_Alw!QGJ#5=U4f(YZc&0
%a{jMf#^3ux7GHRU)Pimp#sR62dy?TJK+(0`{o-E{vP?e{Z!Y?fmzYZZ&WejE0Pa|<Ps1VSYTOY1
?<0M(o=E}AHcA){sEmKTEd@?q%bg>`v;1|?N+P%zX(m6omOxG4K-mCCoK8>15U&QWSAfU)@n^!ks
ws!@i?9*W_u`Plc0>p4H3q;SkLDP$YZDxf^o#ek?l9zt;d~C^j(lIlB_AzAhUGzbzwF)$;ZXRmv7
&{KE1qX%_ji#1C-T)4<;TM54qKh1w>@P)UZYXnTgaX7|o#~0w)EPVfO+jE#U@WUo7*<YRoOqK^Be
2<qTCQvbuxRp^Nj8;$_W^K&Op?VC&7TtbMJlE3JIm+{!0kE1xQ@z+!1E7xZA?-U8nQYrFg>tNbUs
{3j^?$vPa@K-D|WNyyFYBgbd%B(oj6&wH!Sd%MqjsCsYp8B(WF@E7Re6Mggy;2sA6d(ZCpzH-`zR
Jg&g;y<4vQ-b^nnaP^7;~Ab2%(^aSD^xU1)B9x7q`jtbkNV#AfM^6lW}&(#FJoBL%AsMg)FeLGEV
U4LsP_}ml!xp)SmwwfRE(#xv7AIjF1nMD#4yu`H6NluJOcR+>J#g_BgrJ-`nC%-89AeKx5%yHR0t
mX+#K>M3eMGu3cxySp{hW85(MV!@+OSxc}2aD`{vS_EaMkpiKIRpH9YVi0u<>aKMYM}0b}TMsZ8&
5o5<%iZ%9W06GmMxYt(x|sMYMeYk<?^4=86xN;Q3o6N=MWFrMYe39>@4DDy=@B%M|F2+CO!qYf4J
P;wWPfHS0|B&7%`2Dv?wbx^09kuIPhj*Un79Tf|xw-j}ktfww=zLgLir?Z(<Shvh+^XKu+D*K3hS
bx9|umdf3ySfq<rWKQ0)zm#PR3`=!An-h3V>H&>{}5HB#O|LH!;j50M0Zg|695FSG5`yCu~*oiT9
?xlRUPz1p(if|ESz`#{j8BeDgBEw01m?vLP^5_3utU9?xPjMN@bHUtbt2pQYD7dJiZU{qbd#HSH*
px!KTF`u5bkrvEt=2UWY~%cYRTnUAI<%wiO8Nv=UScb!wmPTh2}tT92N>D11B6oi+kP=^I(6XkU!
5SB1v_I-^cE!$nXY+HrU+emSWOFC--G0R$fnnTmv?)pVLHZSr$QY$z4z0Wm01_lwjhOo7lOS-D&@
zaziU>fsL0#MR<@md6t<j}gv5pSa}I9Y0EWB>mnYKnGr3?fr83{rjsuTLpt#1&c+&lfYKbZ$09Q8
&vIcqbB<DP^fRG#eo``*=_eQ03=jn{R@qi0BVl4+CSZW1@<+najxFP#gJrryt|PD;`RmZ&(gA-B|
{Vw;!Ku!WR^%L2Gtt%yIq53+HVfTn@W$}qXACX9t|DR9R&@e(ut+9^r(o5_~;6NH^5!w4nINfL)H
>j^)LJawvTQG&u~;<g!Ur^OFDk!jJb6Qn|%Ws#%Gt_aHWHG4KTV==FOL=<vW4B!pn2DNBCkb71cm
>`L)D<Y}6d%ZeZjpOmM4!WGX6;N#`ImdlN?>;j_8BCPTcHJV85x7M^oMCOm`|E*TWiL`sMNF!mEt
O$qt>mUI)9HqBM>w6BRwwF5`7?CZ{K-Pd&&<rBAi-LCf}Gk~jKmw6e_#03vG{*5tqT~5$Px&K^1Q
!|4K4HUIV=At6oFKY;eSj|u{J7AL`<LFYyKjTD0Pr@Yf4LSD63l-i$s%B)JY0$|RJIsiYl&2Y9B%
@Z8?vg|E@`%r$^Ru(F;PE581Ips%x^omXpYp|XLz%{Oj+&@P{P8Dj?KW|aE|?W8Rue^OSPZ&{`m4
C?6@*gixA1yBW7-<>ebv*T(~hWk=Ove!qmr{IP+(F`9lU(0$b@dgp%FqijidQSw?f)A)N(buhyFI
8=h|i%Xjgk_HU*Txs(N@(m8T~QWpSqP#%_kx4Ewt7Lzs2<kd+Q%c%d2-(CtTpu~EwSlCQdlys<+5
<I0-6C~vbQ5XBiad%?j0iAj=NhWAO97a+ux;~PYIG_k<D;q?sI6qIuo={-zL2}o48-3w;<U2w#Uf
=EI4wZhIQ1Socc7e8Ni8e|iIA0I`H;3mDk0SY4P2rS@30I?J$)05!1nP$z-5zOZ<UQpXCQvpe5m7
l=BJD@!g8K|JO%BpiD3<vHzr`>iVSRHg(O6QL^WSGLA;~8xBn604b3L77CCoqR)JWuG6V5#wYAXq
poIGx4U1z{|LA(=1Abx_RmGIBaPrW42`vrXrS@(liddmwPyf`<7Tc7>Rlm=5=_LH0t?OCrUgK*1s
10u06M=nqVs=F$j;n*=$#y^g%#;)%ny%=1~uF!?L-81j@0i1Ra!bmZ{37NM0K4ciT|J|&xo+4bxb
Q^-GbMk=kzG3*!BN@Q=f->&u;8G-9WfHz<Ts1N)u;CQviec>ayYEX?pL)92a_Q`Rzr@F*4228K^X
ma?JKF||dPI^S2@EMsjz!UuYyWZKu<@M;%(WCHIZeV1a!doJW9h)d#t2d7#3ww}LzqN`=9x+_fbz
>C#Gk}j!vkT}NUgN_qJ-o(;hxl-$OOCjtL4Q~iF`V3&Aq)2wPQpoeUq0fUdvdwd?5eQX1d0%Z&z{
3{;3z?&fZw32GDrPL2<_Y<#s({3T#f^hb{lAx34$*h$CbdfO|0`qm?UMZ`C^TFmTY0+8xFEc&$C4
f_hu1>D3*8R@L~4iJL}>a1P~}p<B<qPOdveOEy5C-0L7$SFOn0dILd7R4U2un2H-bfae>B2VH0}n
M*UtR==GYNf$>~4!pzADP(ExAVa#WZuyYsz)JCZE40#*v<MKUx7#zZC3Syxinar>T1JwQoi;wR3u
V>z9TZY>ZOHgqdlqCYfoKOP9l9l;FYjC(A)y?4luupuG8UQukRE-#&4<fDE7_Cu>v5d3p1V(H!=k
)g8czajTu}`POXW$hA%wZpjNA@I?#%K1C*QZa~3DQhZu|Y-age&3EH^p%L#2x0pLud}DI7~@?=?t
Q36=AmIFzn(tRO<GQu?;OodD@6)iyNereeQoyErG&mJ9r8&J)_o50C(CC!^f~7DZ(g5ZY9MJ9m1i
<1nyKr8_@T0<mnD^bcc=})phj9)6t`70EPN6!|tO;o<7GpN)-sQ<6h^;DNr*Y3Ai`Fa@8(PdsAO+
SRVWRxGmNn3gP-AIh9`l1CYiZJ8L-Z7*)D<l>>j3baG#ZHCXF#3)U<Ej0@~l9zNqX6jxt5Zt-}Ql
w@hu?|-upOV9}5bB90scL);uF{0hrhjyY-DO2@B6fqa={zqKrMF;*8E*uapeAKvbz=(j|Mmw}BTc
p<iNUJrtQ`?d5r2FTF4saGfZfR_GVbH|G$TL7Hbibt#5qMbF1(L@@9R0n&5Xce<BE1-7KST@!CV^
Hhi;x{T82GD_W(+r)u*AmQRx=c{r#^jvE!5yguzTdEE_|XU`$~Qc57amw4{8R2%IA@qC~z2~do^o
RJyYYZINt9`7N<vt?7+tpi4FM2IHQNe5CJRn{`+UAQZiYBlod})kkjB3`&Z!EP3(>m$<PL)H3GqF
xysP89IvZ@UwB7e77cl!B*nl*3@pMp&TtJ@MZ(6r$ZBz8!n~R9Hop^Zq1$;<qR9kHdj)a4yhNlHz
)v1g$CX$d_R8kIc3|8XzRcx(Bb)t32{~0}YZ0f*!n!@7n<S?I(C=P%Ahc2a4t{Y<bj%WMyM!g7Q1
O2i-?jr2#y4dZF3hl}Mt+8dYH(dtEArnr)q?xq$CEJ+DQ}$q98-pz9a0ng>tmAqtQeL?ChY(7V7u
~Q2(jIHuzD_QGk2!@s^P(y|3Y4hS+82oi@7dY@L;erza=@Xe+i?t!1V|L&W(tgkYBz4t5vQRvn1S
|--=Y{(XMUp%yreay&K!*bhnZB`kZNmn)!<U2=he>GR<muslhsUdQ#PTZLmR5L@`IAh^@0`>yNX3
h|~rXRLj5J<4~!y4U8LJo21z)`M-+G4F5Qn8P!l%y4S!p+7IYhJFMqM<FXgyS&w)7;%uhAqm70R$
a~7G047IxAbKpM%u4{_ARQYvRmupaiv|q#^+1Cy6?VG=_~YvT42Hqle^UC_>iJi|Nl692&0ov=dP
lR*T77hx^l83@79YAb)%fy~oVXqGBxdi~m=yZdq=(gY*sp_wD)*{SFunp{Ub5x_K)(EA>VFnNzLf
HxTT`n4bQ&myKb|<a&zMORU&Ii_H?8T12RL)`!_62^7)7E@z+&W+AOXN093btGt=eWNTo_kC71-3
azAo7DcEG(<sA%}z>w?OC0$w4|An}<o<VsE84)~(Ll`pwMMZzScVlP}FXi8)P2_!PE8bEr3<5FHD
hT?A{ST%y%MlhbiYuk>O@%#<Q0|`3Sldu=OC(ywj0wQq@J1r8X`yI3jAP@(4(#i=p7E)x|W{Qk(P
bdxZM+)CiprJlCW18pRE#W{;vuh5=fTZbbXl$K~NGgU8V*6+4!My@R#17dL0Z0P3-i#*`X#h%BPN
Ge0GF_6_AA065(!?N7+**#IBe3W3O_F>p{JWp-CnS|!%8z|@Ei{n(LBHXvpur{t6%F6SMO>Cky;f
IyLy1L^(Ov60!OLgk9YEbV19ktZ7)iGJYNs;7hEYju6ziGXDuYJ-QR_K+MQypM1`2(5Z-wyOfVJ3
;14ep>fcR!Es6Ff^WH|VoqwANxlJU_L6)~u1J71tb=^b9svm&F-Dt>&5Uso7_p-n*<=w|;eGC9b#
sDD#i|JJF0qv|^>as5zM)NSwp``)GNTj~bN->BPE-rBHX6ma_MMsTkI69c6^-hsk~ON@o_=ur#$y
4D{@@}q0xKvpXrUglB;QW(W0?8c&}BTR(S4@reyU;_qZ8bsIy+f)VSq<r2@z0i2EQs#gy<uNK=UT
=D7K0yZ`Ne}p*Fwmw=Zb2DPV_P|xhp!j`gY8Vc<C1J*eTmHjGQG7o4rx=t(poy!Ic}~XptpO;0>j
uq+Zr-xgJb~bDeB@hxztaOHyapY6AxuCTuE@!Bw87Eh5|1QTSFAXhK3$Y56AM8xgjgLbmCnemQ8_
ys4SsyGBmyYB%n7ex6t&$jJ6b7-R{;(?UtxV8QajW1_7&UU*BL|S&uJpWV+#LpO3sKS7_}6OcRE?
S;P6iOxQ`CSz1)T7vxAIsSf&{WR}k%EwEC%lk1<<n+s9|V<lV&%!oVqKAEItzO;P~i#f0`P>8}G6
|9jr2mlO}5iZWw92$zeN}xjk(QLL3KCH5jEz3gE!4D8H9z8msZDFB=@myg6Jlk$c8M7%FIfGVqiB
jy`FOqRd>g@2Ki^4CO#;K0T4T&V9m*Sr_1rzK3a-tgB?#RVhMfDy`f=QmRnqW?2e!vlTLNzuD)Ul
Zvc@TugU>XWk4K=99Lblf+o}wEWEYBDuTR6bbY79+B*nW(5d4e}S=s*DYqO9M@&Km?_C~7)jeZ?`
w)KQa?pKOnCO+F-?YtW+~e+nqt2pPgLM@+_dEz7GH`#9i+$)NGD6}&SB26CUkXmUdv=d*mJc~ITb
Tujy^haQq>P&QXZwLr+!5*Fs}CL7-awunYf0-shC@j=(`9EBc*4lJsOU9zzl88L1ei=am$(!tT8u
MG(@se=UB^ka&iNf<|{R8fxLOG*zHh$qII9?obd4*F`3=Y@6n6E=jCz$f_k_uaIydP<${F%je`;s
Xb)`rIkrQuKq(Geq|Cv!_Uvj0xg*cY<|?g%PMGAIGyTXCmq%jAB5bOv1V=k>bkpv>@VS5l_RZ-VG
KJny#)H#TUa;wpVaiG=hV!a@wT}X(Qy0)G&E#83j51+xBvTKGYYq*$J0gtZv;WA27~^`%uK5bDnb
FTL_T3JQWIrqK|;LaMyK^hN0|#hf*aE%>SPJybz53*IxxM5pvqAlyn;GE5$Qw1+O_I;Dn=cp}ynM
@qrA8X+<3177q@)jl;vPVqsXR!di3E>>}Bp-NowyMKcaxhxP+E%S4iTw@G0<&6SvQl4b&YY$<kVi
g6UN2h<N;FOxO!?C~tFw75(bvy@f26u9&K_s@b5wg>97x(9fj)_w$B`*G9?&N(bu!J!i|FkfZL`F
K2Ap;^O287dDb&>WZy9MXp*&Wf*tNxb}s>Mh0D6&SyZ`LZ<2lFASZ@_y$KlR5m#XCm~UYzg)3uo_
KZ*JLQlSOh&P-Nw-J9#~IwGDhh9Oh)<hbiB+_D<gv#76{)=gaD04xo9^7IJcZDO-6f3VFj)T9CL|
YQrR`0Jt7$!-z5@o3`#ZvrY6lOB!&~YkWF|g;s6J#=}GTsUxUc2AnGj>D48r5z@h{10~Jc4vzt@A
jLy+R<We66#XnX_^2yZQ+3nrk!1|EtkP&JXv|F7{tJQ9G4-vcx?W<rKkM(8A5`(=eziW#j*vbpsZ
Y_aeR~L=8W6lb%OROiik-KU@6=iK~$$3k3RK8!-P!-&RX7o-vwN(gDiVlkO0HNT(fC;b~JzI*mCB
xnjrsK!%gU*rrq<bizxbqX^(0zn=Rwt3xB8gYW)mNK&1W`|qs@kS8KBcOPwhNaAFMzD~c7DMuhE8
j?i1tlzu$60IxpD*3z+D(YEWGD&=g6)?$N|K`tu1MZOD2qom_`cQ0VNbCnkRIwLzIF9c{lZ?a%&>
VH<qGJP$>Z$hdJKrE5(@-11!H(iZS+M8U9o$AaIwilf-s%iwFXZMa0KS5dnQHB0d^LepkTzDmWzz
!IDBT!MTGmks6MQ3!T4GmLo$Ma8lovlISX1b8mp<m0BuqL5Q{Zx=>_tp3L*53{4~+Zcu<(12az(b
Whuj9k<Kax**|V$)mMKxVfGU4ZE!Hl~Z0w!U3s*{09dv6_enQXuZ*aFS7I_82>d;VPJc;aVeyVGc
hAOh$sE_psyq+anYl`S;hri{)>5?QY7zq3^-e8y*?^Dh60sCx@tyaR9nGMk#dQnLDy5X72tY8Z<b
~%B0KY~?EOATit#dCaKL4X)NZNz>2yB{@}h+uwkGKkI|$|XcvRqDV@QUD;}}CuPvVjyXs9Z<@k4A
DB}x%4j5TyEimAL8)t)_86WfL~98Oa>28K~o+mRE7Q?`)Yr$t$WYWObSMzPv4+L<nbU6ACRWE`06
1gK>>Z64!AB5+$%pWV+S9|LG{EG_hQ4yQNH7U0q14P!nQ_mljHObhaH<i<zkD|vEP?V}?ty4nqZ2
C^xl@Uh0#NHSoVF>rmz4dNxYJ{&LBMVZXc?o)Ed&4ViN0wgMdplZ1I-=PULJQxotOg09kr`X3rzt
4D#vm6qt5K8Wb$cpHavv-4oietC`dGYp*-Q(RdEuE{X|Bt`__uwznsgvNh->c%3!dz~^Ga9PhcW@
u6b|{~T`whH+myhVc+8g*c61Dj6*ca4*G*OY5*pRwsoQhmRG-|+oAq;`2gc)rLLvJDfkP*-_RYq2
Xg}Q@tlPpd$`DM_z41hgz<pdHBma<<tyH<dvEtCfYwIL4*4$hqkw_g08k(~yn1Tk|*lT|RTT&69O
G=dt?00bTRuyK0RDw5=5SP7OTRuSGa!_BcGl>J{mTrHN!VTOxFuv!c;%&Sd@-cj-rOfbPb(J#%_!
g3uMabAhyMu_b3s=UcjpY$`7Y(V*Vyvz#_4gRY+0bb;$XC|n?bQjcuu$K|(DTH#u%u!*drwGD$Ij
8HP23=WD{sq3T$GjENoR5-Mw1Q`xxI#$%&9uPu2g2x(GGw5l26+Xv9`cyyK<DcQMXA*8!2(!#EpW
AWZ$~E*HVbI#0M#OYolo96SOI#oO*ca^0AuBd$`A9=hma9NFkosCPiRmLC54=zy4qgZzsI);oFl;
9zkT+fI?`&Pcz;tH)6i*38iod5A_Cfo{`%`}`RlK!e!3I+EYNV0b)yZrVG1_nV}>=y`ys$AEer@y
@owdic|x5{&p4q7F^718lrNeT#5@NS#xybM$0T@h@Pg0)<^*NLrFveL`JBp9ueVrxI^%$ON<pb6j
e4{d$Bv-A5!}V=V2Ky89^63xa#LENupSH^V|l5RWa2?kEN8QHBuRxVFWr7PRAtBTlA-IxH1ja(LM
M2_ulkmpJE-kH7gh}qCNu!96V(=96$y-ZOC21jLR2-_z9~`<oD)m$D}xZJHZ(zU;?~=PyA2++j;8
t-Q(xJL72uPOVH%b=h)I?w12|KA$zh2-o1pH>5+s#!MYrW_8(A=Jn=NuYMxyBj+9$^|ag|!27ag}
u`ZRbT@qrF2Q+>F)9ZL3~Z3A8jIo9+HeT0}~HS{6Z6czXyEn)(tF3f}?)hL(BQob8eW0Y1Ud6h;(
@p$SuehL=D<6(Eu+!Rf(iHVVYQg}5rfG1=iOC?00e8C2_sT{Y?&)cZ9Yqu(X8ZNSxE~2f-#4czCw
`NuL^pQJ2X=0o!B*QPN-Jr2TJ&aS?Z3G7{!}=8w+1t{ks+yRZR7{ajnMEnNcbnrPO{9)DL8pm$J!
$Yap#%}BmYDqDdq<5MlX2geW=i2?Vfg)Y(6GK@yw~cZZq);+hNX2@0Mnm5d@wP8^FqL2csw{H_}S
4F$kROks8&Z#V>}ZM^X8#(QI&mT&h2hj(E^w?I^JP8SD1x~xknl(dLN0W6=ncPw95?4<HZn(i0AY
_)no<{N?091VZkYR=^R}l3UmPU(dYlKzsjzd129n$B{;qY16~@A`ur}F9wTtFYHp#-zax`xp$H_Q
mE3Uf-klVO@dDU|*{pyeKy7JME#s^iDn(`%wjb784p#>^vgEFE4Em1U`h)auG13_NSN&jV+ue%D*
B;CA&WDW^i$B=o1j*XgQt52Anggq{XBjE&Z0jS<jan7+@`}gi|7oY39;a1DH5Y9?;D}S?P1D<W=w
K;80L3kG9aGsmOQ#z5YdzQe%}Q<ZgLZe)noPJ8@vwg3)dc^YbZ!p&Jk$xzmIZOXGAmu{ba}nPAfo
T+O=u`}PjtS|Or`w9)DKFJ#=<>`^J;3`Lo1$4hOuZGhRSIsagNL6AFFgJ3}DcaX10KiJn1L5wn)8
WlfX#wa2e1l3!Lwt=r2}^LV$Yfx~0=bgv(@+#H5LtC(G+Za-PxF@nA;GJvAd*B&NU!GbGGgTUae9
Wen-Kl4-n}l~N)d-{g2wo`mB2)!v%_eA=WnRMTZk2EHG-=PaxstA!)LHlcvH-#$MM$ZP?ewEn{qR
??XHEEQQm%|k|37JWd&1v#5iSM&!vEA;iG<c3|%FP5SdM>0khvipqCu+wN+k(^!a$rV)$B#25hlL
r&2UId!RXbGE_7)k6wr+$M|bLclMCruhE!mxAm256R}agnK&Q{%O@a)w=*92Tm<gcGHy3?q&S+O>
=kMAF(5J5)B7vPdO$F2eCwHKQ_=Y9&^-3ZqJ=hOfFga2a#sLGu9UZL@n+aEm7}8*1}JPU{5E|2kx
S5UAL$Ms`X%A>{L`y|>8WAj<m&ZAPJutb1-@m<5YCV)jK(jIQ!fwt*w-z>aE5M#@yvYY5=#bj^ge
(7ZT##A;Wq?aF0ZRAtg(L;M&k;2nd-g_-U<I$FGfg=g`26k8c`>+r?_J2kYB#!&`*p(NBMk_RDu_
3VH^_`{JbG1t%xi-@*{99{#zD9u_GqX3g|j0`qF6*ftr@oTh@y921U0UoU(lrJ0R3>sXgs$!8-xL
f8W(Lz~W9K<PRazRuW4w-`*4)I(b4wXKWkLjyyudxSg#1csC5Ly3Xm$ckxTtT{2{5;C<gM*{CJhZ
7DRz%0>x)9Iu>s2Bnf;RCr$r~)0Jg1z)h<M}{D%x)H34IP_o44IIg+3~C*qk?%nMI_aF7I-gt`wl
Z!qv&rl5^xrdpbOAr1UaMsE-megEQZON@Y%cx?E+gKqmP`N<9MzU1g^i&(F`X)MB+n{dLcfwn=Ex
?xckbV+#lX1=2aq@0WZPOmg8BI-8;KA6ueHX^Rd-!^9CaOw)XZlWHoJlj`&;qh2vnY(nOc&E_)CO
Ctp`yXns+!d!$vSEPLWG-(y2bs<XIFvd4|@B-vL%29v@e8G#P_*mu({+y5LNG@8zJ7J2*gI2H<T@
Yu!$|xNy!VS%NK#CYsJa}?4;4#U>=bU_nPuW&k+y)`(av7y&@j73XJ#mCxWlyeG>Evl^gns%d+EG
3vDFPuQ+ryW^!$6$L29gD*0p@<6CHmo229ijQVFx}IB6CY}kH)Ae<xi#wqc=n$!Heu!k;F^1&&=l
uFCc=C9HC=O=!__tQ-+sdk{08f;u}Caz<kcwANn-o5r`2YOn${=2)}C1r4>9QdVZi1*CSD3XJ(?i
1RZfTnX#nL2S7oI=E?tD?InvTY8YrIeUM1ZXTFxg0<c*HtMtWjMcbeiT$mYaQal`t@K-KlVE9?;*
zP>e1J{FY%Ta>;FlKXh_J&r3^b7(`jxbLC?S@p|>bsDuOnBrp%oOLs(%jB%&MNy<WOOrCBb?}sR`
karzLo+U)5yRjrd7t{D?mYLkpf`QK5WQJ(8K1op70)O=F29c@l$k*L>$0<AU4~^`U06>^seCFWHn
#dPtX$%r}dVNY{bMs(twTs;{3fjv>1<aKD~la$PPW(UoweQ&Cv(@a4uvmG&p5`T%NtK51&9!Pao2
7A3nhik1~#IDx0l?^B4a_HjQkj7-aOA3?V7)J<`vmVA6$Xh1puvfM)3&_V^o}AR%9f;CpYFuE~N~
-Xub!EC@LNP>%6{@VP9<;8Va6M1oEjLGX+i2NXq}p%swW;u|8$Z_P=%6s_uAYoBz%b#8#Zda^|_X
}yvd7`o~}W-|b~<<1hRw!z(naOeqPl|m*o#5QjP*GZ0v71w5iOpj@~7O(_tnZCdyodkF1HIhpZvh
emF-{3Q=F>CF$5eSRBFeBuDDIens<d-&4V?N9nml{Aic_$$J(Jd1V^W}jj%N)ulaGKJUVep>S1ci
vG7#y^Y_gldmq<ZOc(u9iTnuIsl@U-_;<~$LdS}HiygPXXxnWZE3oh)JGm%LCPm%2)Evntb>{z?&
B^w+hn^od%&%Ff@sIQyA$ueir44(|N&?Dg>M=gYG<7w2!^T%d)?)gGRc!r(z@G$OPHJk=)!Me#_9
(?VYhz&=XZ!vq}HFJqQZfaAO1?*1KyV5D7#ZAm!c-Ng4lp1<HF1ZIMAZ*b_z68T(pBSHeM2v|7+G
+wS?&)`k&^S5s<PtV_+y&t|l{r>zp#S)ach8h@r9ts5F<E!(Z&cw%e=kG6QVi$iqe>a4Ugp>ab#i
mIzl&m5FVK`i@$LIopyfH!LIxYFrEeH?NOHGlss<!89?|-~Md;ZJwS7)tf=Wn<;%WA<-`3!xH&od
5xf$8q{e!t3IpZ+|2arW-=2N=|WWpajlKa{M<5Qu>1Qs7)595KjLqlFPpC66n-ahU=kt7tH4Od0-
&*_pQS67dtHJ(hE=ZjRkF_ff^AP-Ygawuuo7y=H83P0)D)9vM0k;=nKgnrg+05lR^&tHyNYO|;1}
%^HK$o!XFhtlQ`iSc_^v`hms3dqbxuzbUj4?B3|Z6BUjvPHM{tyJAL^v*i-^Y=KXGew}ixi+n*@u
l<?zY$GcR0IYmK1<8y=3*5jw3(O7tpxEYJEoEp1FN{(}CaLtC={@I+f!vOm-d9dSpzf>85L7VS7o
SaWU=9wA?9eiRv87m{@K^-Ti8Z>+a}38sct%ozJf&Mo`TYefs+HiN;||mLK142~2p!WPzI+oQfpI
>Ks&uCV2MdW&a4d5Bp=e@I1L`N>%?HBv_-+zP509^ck4eG?H*Cs-F5e+h_W#D_ple|K=(wFMfvcL
Vgm+&dE^Uy}LFWY7T#Uyt=D&$&$l0ukBf`^JoC#0^cY^ZYC!L43Pb$$>vAjzq&s!u(=BQ0+rYJVy
tV}yDd|ssn_&BO)<YcL|fYs(QJ=YJ<jfRNIo@^a*KhP1KrD8xWU|yDGfq)D7#Xj~?Bnx&m;Adn`k
!0Ju!cxldKu<uXBTAA?U(KY&P#yAN)tZ^2bWMptV@aFN`Zb>-cQ?qgv8rUM{Z+}B(2!r9fLRiF1>
gc+S8=cX&cHP9bl8-t!5t1vTsT`avwE$i3@>j0=VtERnrM#Sv90AHjlkhDWbP`WqHiyVf>uXG;nO
VOGUFLC-``;MgJBQL%o@@je6eYolE4EFS!-q;N3t8z_(s+}0r#xOh61M;T|rn<_!3+Sc?F25P#rN
fAPEz-ECowQt>76FT49w(DQ!`Hv6h}m@ou~EPwX>F&P@iZb=$cG_zGu0D0Wzj)cEq7tqLEnmPn2o
K!uluSUs}cDOz{&?4x%`ShU|m+wFqRyKq8Hk+KHgZ8`a5Aas)^00&Aq4Dg#sD`v&TI_I;Tx)}P#$
)XXF0#`M%FtzmbBv8Dm&x~HpwqLaj()h0cX>9=eG697y>9@?qqh0!2W$8awiGx^@^P^U6#G+RMh+
Nk-P@{*+iB@xIVhi&7FLl7<8PC4vWUp_;LgULu-huYsOef@9f+y*9j{bdU{xzY$wDXyham7Dn^g~
|2WjtyE4#Z3HeH)`xl8KlAq>)4+jm>vNH){;xin4!01UOR0-|86|=?BlLEun}<v0Ru*VvAoFmGeT
Ysb!8%soX%}4YRM`Vsy8UNO+Cmz-+%0!xk|LWCOo4ABY#P7|`ZdspULCGxe+>+x7ivLMH6Er8*D0
^oBj3@dDoPd^RbVBQaPMmk7Cx)F+%SwKIt4RPq~Jz%x8q&<q?yA;hRE_a9z}<!Ew&XzV@NP(OiVz
(SG=NYe~HeCcahF?mtRG@(95R6XqZ;;;LnJtN{YaDg0z<ZJe_pg_y~siQu1)h9Q&vtJt0>o4=>P=
A&KvpNi5HHVbEUSwqwgX*|ajX2oJG1@)bH_urtb|2?X4m-}S<o>NIcR@!)O?@Qeg~m`<53$K%I&n
BM&yIvOzU6~y!#=YPV-9?Us`eIr3;`eiSJ-bizm1#I)8@;;Z^yq!O~gkz2y5sRv64->micNCb|P8
;VMGrtlW{H^g2~yzUY#Z5GUOA%!)%B!X1UVi5*5>W>>elAuA_QFpth!|ccP(>&|C!`M$UL78goRx
3a=_3;IT<c5m7q=)UGgZeYt{-+NEu%@I(k}(b&MaAl{^W;Np_@xJfuv-(ht_5{E0;6XUEA{kMpx3
oAMd0Zp9;SN2ftU`qrB?=&RX(SnRMl9s(mb=SD2Fk(W`IEszPGRoDdvX=Ecv>Xoe&^z&)4MU6RK^
oWU&jBO1;9>|qwb7#<q#MS+h2*fU-6)ZKns0NS;vQ_$Srd;%5X>o@si-#*C<_PNY!+Mt6$(~Goxo
SS-^Adq_BzBKHf$RtS^YXG(Z)vB|C2jJ^$C4R;{<~bljc~}%^?+&GP1{N9(F7&tfHSc|HG~bXfL1
|FEi3KP8!OWV@DMW$PNCT*O{);VV2@9T?U(^kW`sz<-x&<OhfM#+SgrWZ{A)GPk%bSJbh1>6MV|D
PEKDlD9w&|6tK-lfJPs{SY{>P!p{=4Nk%V_I3wjqi!Wa2)*{o^C*sxt<Qzs<d!!R-;XpPMeEWWJ`
SOBbi`Ex(b8(rLGqTPV2qMEaDB}v|F2#ih+iSovO|^PKs|7=&lMFzBja!!%+iohb{EPF8cdt%=Az
L&w*1A9JbVym&>2kO^4)1}vwk1RT<K@d{=jhoPv-30*(b(nr<*PH@ROjg14r|_g)kU2j&Q4#P;i9
=M>{BgGOn`^&9E}pn<>^q6H$T2=V(cyQ$C{`fL|m|#Jpi1ed!kL#0M@gF9_<Gm;T}Y3M@fws-}T{
Dk6(8O7)S?G5MSN5+x*LP*rZY?LD$+=*aX%ewAlPBWQH75QHY?6nj3F1D{ZJ!1eOg;1hh|yCKo}u
9wSZ`H~AeQ6=RMLpO3^rZ!THh0?wb)c~La16HDi1EOfM+s>_O1k1h6lhXbXYP>8-U9Y(&?VOxT*g
6$0#<D7FGu>gCHP)Q*gVw`j)ObY`umIzA2<qAEk-k>T9QQcncg-gkst1>^8-?=EK#Sjk!U~WZ<K)
Ty6syHH6`fI+V!!&@nP$1mqtLqywz+smhQmu(rD1+64L;Q$^Ln{irY334`J%<&zcpFGhfa(CdPEV
2QJVbgEwKilm0h-fpZ(2#Fi7FbjFRjQ^Bc(|D{@}2!S!Url8=9@`a|mFJ!u8+uNn{uYeuXI4!Q*e
$Q0d`*a2!0<quw-Hb#{BxpZuW5DH=Y|LuH|=k_(Jdl!(%gdU8Cz)L?@B6l~Noknxp)7T1GV&V4Gd
e3(x|x_URKiTCx!vXgn=D4Aj;Ymr#zahnqX3InZ}15~Twkdc_#9;tcghCf@)N6C`xl8PMQmMl2xB
$6vM58*D+5~fv6-pCGwJYfCd;X|17=_%$o5c>f>5fs{T!eZB0SqY5@Cn_=!dtz2YtD^!nI5A+xtG
CZJ%|N9$tL&r9G(**TTzOxNXi%X$RE75j7VzIH*q%^wI&k_>Z6(5_GfP?InH%;fsz(et*grj6q*#
-#hsto&HiGA2yT?8ScydPKk?GD#8GWQXZu`D#2GbyG;Theb$;>}GWs!l+s+?eh=`-SV_js3kG2M2
Ba?A35x#ufoLTZm$&8H_vV;t;pF-}wWP&cq<D-ENjnTXk9zeG5PI4ID*>_MGwUBW;COX@!tLEfJ-
>1|gr%p-`R=F+oOBude)RTvf8RF-fG5!n@ZV|xe5ZGnxsA#Jh$eX)sTYO~7rA!O%pDJrfS*6jCiK
m%La;hiD)B7@&bVM$0139ah{eUh3swQTpQ_^1Yn0!R@pZfs2csj1C_(uE|&s{hT5Kf{J_)!Q{=|K
7!do(3`ijkd93*PPp~&~ey2jjkv<_fr-IqbSnnN`pbIN~Ch@;zZPG0q@IKO@3>zXwxW+*f(Alh&U
iB>PhS(17-2m@sv%;NC;EwWu=vpmJBRsjX@C19D4;H?}BX*UVc803V1=n?1{s;3ib<E7}KCz+BZS
aH}HOyZSUUy`u8}a^htFG*mefem|XgkavnQ;N&vty+ZJ=bTz>!FMn!j(joE34sE?T8O_!4O#9QM&
95s9_C25VVRxx|GF?xq%4UxS|8n}#U2eMer)lS8Qm$DrhlNX8bX~!ne>|dCfviQ%s2I6Vp`A1$?8
An)B2H6=K(e(riXjsr`b&N=xXn1R^7C}>pu!cb-t4~CcSVi$v7;jiWq6l|Omes6p_vaw<rn{4YtQ
ai%8h*xsXSPR`GXu(DrJ*=mD@t&2M=7a^-XwH|+>k~+h<9lCCW<#`=eWZVFQd&7LbYPQs`TaFJV7
<9vaElXSrJS`Pi`d@UC+4><jw_?u$y(CYwJK-QXT(}oLU?msPXnmV94$@DNk!|t~NoXz8Z!J;GMz
v8859U5qSI53y5WT`SSU}w~xE6R*Mbn*eACV0-ewkYEqr)blk*BO{hg10sTM7Un|8VJeVQAsK(|d
%UX}-omT;vw3cA?(2JPQHq_);_*$`iAX64>SSGF%bZTQ;JLj-7wv@NQXy*ly+6`L`rBUP$sWd2Gr
C4X-MoPe}obwI$w2!CBkS7;XORg&L?;wukcSREmN@_%eWe(E6w83P0ZK=F4HX&VD7OPRX{JQ_-Y4
2+9AsS--^M8IrdcG$7?o0<?%j+}-3~V1G?19q^stJpI20CeC@x4^>!6O}1KmrHe_j|{PQBENhn-6
=P3;|a|3Uepii>jyFa+Q58JwlkJoEV1z2bI$2pUSGqp(5b56~v9N-i?z78QNsRdT(_~p{|{uH_a0
V`XK$JKwdrt^~Pkgjtdd~if>Dl;U_tR;o-Pg$s-L|iewzGilh<|Mta@xjNnkCD<g6btVygZp@&M{
PW6m~ew|~@#6M9P_rHkpk+Rg~Acf??cq!^T0paI5DP5Ak?I6X}&5=6wD)&~h7&lIFOMESC8kTjgS
T}BX9*TxN&fA_VE2k?Rt`6N$TJ!uiu`jC##p$N1VMB#`mA6=Si%@Vmm%W+cP%4q0tbVa8F`3<T)C
xj!^HODl9|eLs)Xo9n26mJ!tK&@WN#MXa#CW_$RU4u_T3aA*Smj7@vlJZ05@VW@uNeH34p6P&6>+
7EA(oeNK1KhHIFs`g4sKIL9vZw8W982(9H?wxTq&V?_E{}IST%g>do7=?_IN^j&J8|#aa96?Y-mA
L7#Lw=&<Aihg&7y2@D8m~QR#k$H?i}0xmHduDsH{@ZnKQJR4yU<<P9msriAp`9~V(7u*v-s+tRb`
Q{YL;>$>QptNwsnBR_KLJHkxejX;!(?>ClnBG7RN6%~J8tkb~BZf&?RkRux96ri9t<|`QkUgV{gk
haR0=@rO0OpMGdV}wKK(Y^SlC=FhC+wF1OL6MW;KBVSWw^98{t!~X_q8O2bNXM~hJHu7c@kRUkDu
35_Roi&I-2zxe8=CP$scuRtm>Er~?~8HfZPCo%{1xA|Q{>=Aum%YhMBXH!cmb#lL>*&W`9ITDVwr
Oe?;yi?%AM9x%R(>O95^8UB>FNElcPVO@b~5%7OX0vjb90VXGAy=!GH6+tfAZq$t_Xa6HvBq<g1p
Pk5d!p3m_YkpbB<|{Dy^3x?qrA{nyXI_$H>Se`WHnA}Tdi5+kMJqo57KQJ;KLginMqCZU%g=_W1N
0aaHJ+5*gInvI3OJ`DgG)!y)lFQl!*2Vn9lO!|!OP=+79;fZg%-BUrs_nsQCPg*LXvd`?0z`Pop&
!b_31?WrfEzVV;-5%sy#F4spQ#krCRTPjUE+YJFF`;)yOrv#^+)vVLIHZ++Le!?oay{RHQ=cw_BR
CR%)p^cHo}Djl$-v~7;PU(T4{bDU1RqwD>jbTy#5FIem?~DA{~}kHP-y^38OVCU=nr|k@FAQQiLs
MyxV$I7cfq~%#CGHR!^Lb>sPnub#Sj>1K|38*44^o%ol0o;k{_?I80%^6FM>n{{Q`10kXayS`1Lp
QOr%--UiIRYI4Mi`mO+KPpv_Se^TNA-svekM!M-R>V$s8S6OUP<h22O-eOV?JB?P2NX495$S8pV)
mee5Y0GfJ&5W3q1K9Z?A?;LI1<*%hCG&Cv!tU~ndtVX@ZS`EG1EJ7d_lw3f5let3aDVdkcv<UK9X
Yf0pc`_&#H!#?R_<SWouXH6vHzJ{m;~S&myP1<n3H;*cOOZmUB^!Isp<3ki`!X@&vwUX<VWG$?hS
<O%SM03rJfjoJ+7R-sdjDYHn=GxafDketU13<Ng;Bdre<;d7KLI@Q%=Tb)$4cw20%3}*OH2fj(V%
mgfU1wNR^>+CngW>w9UKT9UagsjRi_bjA_1WGedn}WxzvyEbQ&eDvQc*Rt9!W>_fWP6@72?WHt}c
}&I*m-9IyE4b5z@B&B%2?RO&#M;tOnweTJ5Hb|!Iw`~JPI7+WLjl;pZ}?4Qra+Jg$#ssMFG6<1G{
t*3F!q9<}H*|;ocr5F>^rnF_HXB_LIW!`#yF8Q-*nQ6$gc_W#Tn(!$0Z7hz-BwKSsGl>f%batmZ|
AMuE^Y|liq9S4x%@er*_SF0g4pK&9`XWqZ^$^?)>TQR{4lL;A4k(bK3LK?`<6Rc^-_MY`C#B*`$s
#~|Xz*Pi2EnuakI8z6pKfwKzKPdG$#=e?spP?*eU1{URI1Lkis84+9hq+4s$J4X(rb!oD#rN*eJq
>JAf00X8e!GGOiL?ZI>sm$2HxyV$l+OFM<qGNe?Tv*DN<S~Xu@(XW7sYj>FulF-J9=~p(Y06!Q1L
!m1%Jexc*bV!j7p!a;JFz{j+^ez<hcB@@2~o3%|&&1!KRw9>v)41i#!+I5L~3K5mYHszGa~I1q6S
kj_dnURmaM6j~=J)48nz<71&>FogFSl+d1f4892tO^59}t#-19B3hJgEvAPZcC>#&^XOv>--teXA
$}8vY5ZtlT04@NTv*1}>`CX*frsL7N2;g{v`FuS<uMvH)P~>MTh;uxANZ={`nAT(@j*A#m1R0u{-
<Mjl0hXK^Iu)vAAbw*zq(qYm*v%cCnj%8yWf2=E2wb(!wZtR+(Dc_!+-e3TJuJ5+z5^uL7RVErMl
Vhi_=Rz6G^t&*a{ExM)2*X+GlTG2vHEXb8WcrT47U2m>eTq2thV(m)G&Gxc#HKi4MAi>9m)geg7V
QJGq1`{H|EUVP}zk*KhZFhXcl~eiuJuY4xRH6f(`6wRNCau_v%vKl}hc@Qap>SE#F&O8z*@d4MJE
yT^YP#9~<chB;kS1$jE1?h5l~l0dPUViWc=CSXS*1xScqrv;h)j$s%X#-c>h!(@jpMeBSp_4vc?B
f#XtM$o5Wpqkb)3OGkv{dat2)p^Wyc+7SsQRh{XT|1Rv*Bn5lW7<FXqbq`d2XlFsEH5bkk5%nkuG
VqJ#?_t+oWu;Rl<C5(der5rU2oNQH+e}aj&$5Zz?n54AMga*-kKK(+qYzk$-yXQY$-TO;7GNadCU
Vi^f$w~j$qdBP(HOP9&ZBh`}~ezg~PCFeap4zz81HbQBjQg8DQpfG|(>0ipPhWVEk?tXYulRo>8t
h3YFGlDrJ!J@ZjKh6SOIIu$XZVPUN^K@^MN|NObaA7bk>^Y_*FzrGp;s;lo~V_`777Cep{Di^o<M
jxCv~DCOh_;;cmL_$jQ)knCrV(dJy#wcq>BUsi_I7`@YBi1!E$PJvtaZInb5cp~A#tI#G{KVS&nD
YZnh6?<&M3pxU+X})RUM7z)lcNbOUZVLGxJUOYv39#b4j*vV_r>s4ITX+Z}mkunyQIggzIkTX_ny
}udCgqdLy|aY+K99)|f(hpPl@5ORfx0lDj_nIj;ChRp3F(&fJ-p@{MkVDoyuKuQsl1?cJ~0M6X+A
z?sBfa%039Hf*DEE7Z>(+us;Fbe5mk-_jUcSxQDkS<l_+f+79c-_`lH7OJ~MIYb<n}haqK8Va2(1
k{BTgSmI{JVg}pjI|3+fZzPIjig{7(De8bwWkvcOOOf?O+D-ClcwV?3CU@g7`tMsL09=6M|^036q
>su>?<ko~NdboCK78&#1jPc$I{w@S0;TbMtXOjXSb58|z!T+xI*g}GI*(55d>p27OWi#8-y~sf0D
Elt2F`&x-G?SW;>Dtz$B{@wsp7l)2DiLH{nf;<2(+W2u2ld@DF0@J6I4IS(X;S5nsJt~D4EF`AR&
s+wp3rW6?wW08b1D`iw6luoOfj6dwhpw<pIS$a9j|nNlLGu(o}ko2fuMKEy<<g+wgN;8Wg+VZQYT
>awjom_X*w^~i{vDwz+v*HUID}tUwT`+GVt_vXjfxWZ)+PvnC$>&Ie3m`O~z241sWL}(;REMOvYt
SQRbGOXx7^^^&lxzk~kV5h#Wi`(<xq|c*GhiBWkakheL#!F&w%?)MyZ0i~^>|7l9)&!`eCQ3wmV=
i&wdo6HcKF$L-Y>9RNrYTdkJZbysk}NmWu@m@Vltd(y&ED6qyKiy69p0(p)X!k7SU&#<3=tnxCcC
N_nGE?)CXv}O;`DB(7tm2CwtFj^;u5sfMGWC^1bbHx^cAE9C!;b6qyL^l=38BGTM;~XdSjobyS(5
4lC6n~6P)ChB6KjE1#{(gP6_qEFbeoWRz3t7ILk3rUT!+Z*)z{0}z8)xD(i=;@KlSv3gBj0NVizg
VTnX%<no>QJ{GVHSRrSvTGAQN)3ZI@M6iEJJeGNU;s13^)sY8*;KlFUDdQ+RM=lv`=7x@TqLRr|q
;9w~?7ac1NaHDj!pKFJqvgp-#D#C~ab%c!fHO0E!&b6eXc8s|K$W&)`#Z)Y}<20+qhM<g~Ow}xsP
JFL@ZMY-H;|6hOCXeK8Ueli)W+8wK35B}Giv^kzCmPse0S{6l~*0%baY@VX<b1G^o)*_W#;9SHHM
obbZdX)1P65U>H3zf8M{a&X#=+(nbZ^ppM#pSWfIjj-}Yb5gFOR{8>VSsptJpice$)r<a(?xpAn@
=e(rrhv_y}!v#nAvvn9o@8faYjHd9uyJxETb0HM3jo6n(2vnbZAa@Vg$UWa{)gY!Qg2t;`fRL{)*
_E%}f#dv#GSj9zhAbAI0#ZT!6w!4fBtbBr@8Ru*<BfhFIGG-7;e%Sw5s8)U_msUu{WVtdVnr8Td3
#XK2xCJc8ba;z&`!bnwtZ8&UgYrl%@No$&&=3?TJH1+C{IQOgMf8i73eFqE#Z6atvuN;6yTUn?Ru
;h9z$J3#|02aMl4&%#l8Vz}W28$3wN_<;!Qjn!49Mqg1BDl#V!c6uQ3qG?KOpHP&JJ686m?2yhzv
u0x+OD-vbfb3y<ifbQU{1!FbmSj&PnlcBtOvlK*32SC@pM_?>(<WprCKPhDTD}z!=Z1KI?gs0VSv
((2Vs;3_j4P=&gydichXcV=bfTJ|gqx!{);nH`b@$(I^X3GZZg=N7xurP?5W>jvI(m9yyzXsH4J>
23i7Rr!IO1mWF^^)8>;pmGb-1!QVmftbPA`m{z<8#Ks%^HzRHGW!kt`t|*irbD&o8?NN4pOEbB$F
E<)3M=TA8c#QFPNzD}#!LVVvT%PIdiJPd5aKi>tBadUi@R6@^$gNNN6r4RAw*_7XNe=s1MU%56>J
s<G)?-i4)k36}zCxG187%NPfB@eQhAbE7kO(q~qK4#?^-+~0op$2Y75A*kV#wk{Gi6m6*7SGK>XR
aVx&{u&r=#s|I)T%7DgOxiUP)eDV&m?AkJQek2fTt@(oq#wgZ29%jFI~j6HCAT?^6=*AmCzpvDQ7
~T>rA)3Oot`N9g@ZMQH4?>a(6hJfl&bQt@!BuFm@P|M=gkzm8_C<u{~N6n^)ouJ>|r+BeJl^c=K!
gE{yd-M%S%*O^-N=4&TP+Cc;lNqFR(<zZBa#gyg_psfc>mY7qfURa-#($8P^Gi*fr&wE|YjJT5q|
{VHPp!2SwQu;nx&&L=R?!tYCoVd@;K1&KGfdof+vto$xz2Wx>|{#%7aj9PQXvR_v&MuMog0S0Y1c
pxjL(6gN#GCD>iO=D=X_+C%&}UW=hgx?bVUIXry*4k^gRJHZ;bPW?CWgu{QK^VNbyna9dLl;$esm
<3WmX)mhZRL=zA+)jUlh=MHa=D;Mrjjlofad0)h2#|i(cbsF7EHg!qLdBU<43n%5Of0PfC}0)XNm
@oTK{lM#5P*cJdzezhA`xiSZI8QRL(sb%<B_6!>cvgEgq>c<v}$;PW$5Q~$L7_DtWfdl4>U6u8J{
aO1nZj?e_ERGaYWqNmuw4@noAx=b2j8ksA@-Kg61TFP;ZIYm|a)IcVe$kOn*y#rN!<EvSVKfTyiX
98c})+3g`8nz^K|HLwWVpv(VgIL9^jl++fOmg_%!hPrgZAA<Cr-Mf?n-w~8LG*9Vz_(yD=qa{F<4
0e@-b4pgCo-tr=)*q9>^oAs2(h`%4@b))KtGnXCN8thP10}m#A<VMRMy~XV24Z~q?X_V5jaLvW%)
gIl+ZFoN~XB*!uvwv@y-#tP~)iT@2T~XAs34Se%ZEWC+(_rXkh&Yg!x_J{>wH|t}P31*iD?yFdP3
0FWePSEz4D0cMHUCK`V&c5zAPBT|<rgyS5-PD<4<8iDV3|GUQFj3?MJ{Wr{fq0)Le&Qv<m<HaGIE
1TI4^R|pIq(Hg{+*yiTn_4Z5AdN)~$tVMfbRqCR#$~M1H6l2Gi%hKybG3=ajM!3SNEz!7bHkk?iV
JRVR}6hUQmFu_`iqES<PVa(Fzc>}#>G!dC%h=v79>L0$|d=W}k!bWo|gCeVsP|E{Z76L2q4of@J}
*=ebTFc62<2<{Y@W5dma(0CZFZj$drj1g3Z(S?Rl&53DZ=w$Wg<**eSZch{jF$oqZL@AH~1I;~L-
v;Yg>&2!TU6ip5l~JI+K<Y5I-**T#ps273oVB4P6|8!j_qSFR?F#(OHdeK^Ag1k=m>37M+;SE6B^
GqoMKu=I5oDCxo}cJfqkegv_Kf)3zDpA0w9zL`wFT|5BBDLZrBN=H04+3;L+-?QL<YCcGqyd(&>e
OCp!b082fqEQ`azR<qoZ{C#XC}{WI0X#R%al$V6M<w7YpGUwWf6lCATI$+*%W-U8#u=x78HD==tD
NS4RS?=L2AEEq2!8VZQkJ@)7F_bPMvmbnZQriUTOzsWliggbUpiTd4X6^SkF_US5CkHus5+>PY3U
{%maOM&d#6sNJS%`1odh@g>sQaQ=}8RvV7VR9(P2nSonGPqOh+nt~-H-^$N+G#b9wqu2`-n;kxt{
WpOFs~K^t+mqwc@nbfGWMk^3BR_p8a?K^_14gpCfSCS#eEt&!TWd{L^F^q7Xoyk`vVzXala7LN<u
+eFP^pKM_EufDgywpwsAo?7Km`wUE@`aDb8a2zRb2CulttN=_#~o45)*oWjIlI}z-&xn-#dxBDML
3(Y7K6oq1jzU0E<Z9eGBz(uWAZF!!puCOGR-=s`GS05z#3~Bo3WT4n!Hz{45?N<PdWb^o2^s4&@~
8%iW+%O4^Qeia6PrG1B?M%J!t&RUNB_`$nS!4)%oV%cy4BuiptY2n~&KL~y@QuUHu@)WcC#T7;#T
FIcf92ZZTe=L-Y;l7+8@f6CcqX-#{IY{+U+-CeGX(2}Vh`n^tjP<tuQrXv-loR%XT+NTB(JPkVS4
b4)dSvHQD=XjXPoupf6V(v%V8bc@>u%fb{5J}UO?Zk;akls$VI$G$mTs}DCeDSd`Qk}Ahm{1Dk)k
21bLc7dmdd(3uO2g)ovZ?|;UeEGTJS%|9W?UW)>CJFxhPF%#v`mjPG{(WVn9X?XX38k>Y$JQ|LEs
NSX}NQ^Is5_vj*ij;_FI6bLlVY^Lq`1J5S<QiK%&25U7&o1`6Gc)<5KK3_GX{%TZ{ExkKG3MFzS|
$H<0F8BUq69!Qo+N>1dAe$v%Ev1W<F*8Y7h^1^I{qg~$tBEK`tMHNu@!iJjsd8b&ZC51>LtGHZ#~
Svn_IGqEHxHiO}Wib+zAgTJNE0t(oG@fxL-M;3It91Di;P1rLNwr`OnfiWMLY=m}=DMj0fuQI@_@
@Bf4(L6D}Bb!4{R%Df}XZ-L!$<i3-is#|=Y6i1};n6h`w2i?n0rQgOZ9JoAKrG8x_=2OuDGmFM?2
!pB&r&qJC8O&Yj-aK;09=$yBt<FbGehWNDl8~#JA~fRc?^54fPRbg8kQgEcUGc@C>zJH%llkh?qV
P#gcbFnM<JX=ud<i#PhX!6FV6o9vy&ZkA0HiGWv|cQ3}2sKKK~)0q+M@*d_8>r!|D4A{QBsKAG~{
i{`&O&FT+=7Z@$0$0bf1l7Z+#G-@bWazv>=-dzHc0%hPACptIALXP3Xg<D<i??1vv;zJ$(xes+F|
B|FgkyZ2|8@6XQg>BTRvpS^uWO|<n3YDQFm@~=<N-&CG=y3`{Kpz`?i)%o{t&R$s0AJfXbdi(rum
%qF_8=k-U2}-?S11kOar?dCZPA|`22gF$F=b}Xhmwx=?o9Ay|!=NuN=pF6XcW*DwFVEk;8D6}4OF
f4NZFWmOK+nu0_#YiY;rk<aegxmYJ;p?@@SyuGdPSZ6eEI%#D25%HuFf6$>C(>u{T$NIBl<a_pU3
n=PPy)J_H6@yI&JZPNBrLv{~w6|55@nF#Q#Sk53tI<HCm;!$#9VuDej{o@-d;Le9~DC!^?bw6EeK
ybdZA%&()&%$t~Ve;aOs57RMLWe92^Qrp@nI^QVg+9MzPk_YWTiUArTX)=<{yJa#-9`zgiXp^w<y
0Hbwuf+tV7iWAxz*snx63|jc{?DPV+q#vAIc07xVB6#(QqY#B>Wb6xtw3k^?m?hEi+HyL7eetZxF
`tAR2xXYsM0bEJ@kudFv&2f?qC-dwhiR6U!(oU{Wp+F|HY%7+TWPi+K?q+uuVAY7%F$C85rASkO_
u(b#gIZ07#5E>6tv<X=VBU*<5{VC<K%{VT&}ikL{^ycZC}<KxOQTqxvF+ahB7pb2PqtR0`p1G%QQ
uAY4qF?2O*m_+~vWiWSPr=mTc1m3)1q>qv_5AZRxs|kXkA54hm_A1HsdeS42qPk!MZpX-THUgf_(
>Vn0n6+@rRHp<WU*m{DirYvqzk`{+0d{s|3kLXgmX^v{4Sl(2euK)d@0e%Z(qMRvrIS|r=&b4pJ<
$qL|61-@rk(40GG(sbH*!sU7%95TQdnY}EM<YQeQ$X8R02#=ORFO~De1=7=}0yx~fy|fe$yry^04
%H*VsBm58SS!o&M1WyOz&B60xQlcf$0Zg=&Pl$zl^920b>E7Gph>&$1oUnzsDA^KD%Nu`nwz?jm@
JRk<r<AAZd!bF=%L-TcmQ@nJS_bbi)ZkuVzE29$D>JOyKKWT5GBM!vpS!x8MN{AY29rw_25^Cd5H
{yW)8;)oPcn|z&ku?mMi}?8lFBleCVfwF@MFb#r102Gc?-#02`Qkhv-CF`X_+Uqim)O@aSJM6MIe
5fp;i0+?tiFxo9%c^QHyU=tJE>6-VKzg{ASG|1>lSf<=Kf^Y8=DyH|V8)9~vyA!jsXwlAcTz!o_Y
fxG=|W-(+YN|1|v?hctqw;I1V;R5bErje40*t>JSDAB4wh1ZqyBo3?sGUj{GcVx(U4u`_J5SS{$V
3P4#+?<X|JfmPaEaY;sVGu!QfK7=VD2y(M#Z2_HjCW!tdRj)-OX@?uoSCL?5~do!29xbFUi5xA$2
e?)nm8Tdz7(&GvT%%8YIm}Qgp%26Zt?g$1+)Y6<jKHIp$gO7Bfmi`PnPhXvQTqJpY7^4OX4XC0D0
k2@iX@$XX_mXmU(JGp^ltbA)I};ze7E3*<n;`bAwa`M^3Rl)-`vZG_@*IsuoXBd0Vc^iIu3Gj}@-
a@n$nu4%%rLt++E0XC1EHiC_TC=7<!*+fhD~8=4LU2iY(q7r$gK!+mWwN&Nm3X5c({?!GcGoHjt`
(N@e>Xx#`b<;MRZh%RyU<j*3j-Z2E_BR@K0$SfP95m?RYF;ST<v@VY5jR*AhflBA9wUWze%hYx)%
1VUX&~Ge)>Pj3%1lee%5hE7tJgwcPW`z1NchQ!jIFQ|oOB!QLw!Vr9k$OuDfj(yY_29!zFAy#4JO
cDVv?6h>vjKiJgzs}PZ1WQAK!i7*AN6Ed^jjgt72X7%u1Cp`7?=v5;^S@HkO9PF6PFWJeg80w><r
T)(|(?@*9r3#{hq;_4E$lR9rk$?PXfh46aV4z&DMbB0VBE47sP5UdmFV)4WZ~BB8_Q?fJ{TCpRUj
h(+7lla$;7&uiefzy~zrsxrMkR;mQGr!H+!hD@+BoZ?2mZy%#-;D0g(s7=!T^w&IPsjnuRcc$9f`
XLO;m@ulav2%c7bp;%7~=&s<RltD|S_gQuWYopRbzRMZXg-8W?8Mfqn0+NsjAmq^vQVBIK|7#2$g
iGXJ093S=CB}xvTPj|xwzmLf>`v;24CmjF;fGjZ-v{(fENlX15>Y&GwQ)chFkbSB6w1Qtl}RJ0+?
Kd_fiQF0(N{hDsDcOa>KFu?%Kb{@UG<@-vFdFQF-GpqjN4#5ORqD6pll4rQMtFVG*p<lYAE%ebSn
>A|Gp92Iy?Se(tIotZQJBXZKOPf9zZhwT;U;J*kJ!2Pl4MC5x>WI%i;b9UjC-zc~aiw6JrK+b2yY
^qtSo*w~hXm9XV+R&ES*OE8dy7s-9aqSs(A97Q<G>s*p=xL*7#YMYnYAc)r|gX0h9jeCknw{dE2i
v=xz+33mJkoUG?R=)4D&s8U&F*{R$?q~1V}eDYXi>ysEWy0bvy?h#ugzo*zf%c68O#`kzJ0U&Zl`
l&KyOYtb@S+!~VL~%$Sdrs-K4~jan>IM;YUB@)t%O=&nR5<O%cBGp*9^CP6gL{O7>$d;hqx*KZ(R
FG-_o@4bR?bpZduc>B`j<fBHrmN|V)NKML)+4&rXE7CMofqxAR_jwV(N(Bsc7ZUS@dTaFPcq8dNO
Yvh0-Qliv~M(axdsT%qBkUcsn6t*)sX@pWi$aUU;OvqhNq!s3B}TWF*I>&Noj!o-hbx2<+$~Y80F
(fDKqM%utMZxR?NFlZ}QjPQl=RI5fdN#F^o-i6wq8IqO1c0f3;t&a?b`7}(czVJz6_3m!p{Bp*F)
tz;xc3?Pr6Ja6ygaY?Cx*iZ$nGF`Q0h3Ty(FR^(=lcn4@SJtnfHqxSqps)rmR1ip%Wb|=T?Xoeh=
A`Z1xERt<2BxN9!q!{#ebEJKZ{5@gEiIJI^1BSYTh1<GMvR#ZC5IkXfXG9m)Srft&%ViIW2uVPH#
x?;77H%AzC8<lvB|@DqKD*<A>(rOJ^u|(g`if8eXs{@-R%6O{$k44`caMV$%h@w`bC2<C4I&bUP6
7SsbtGHt}>O#I7w%sNxckJKW$?}{Y7RAH6J#uUG~Ii*ykT+_FCJDJ66KCVVO^IS<8?u_svF|6~WY
ZF=@2-)VrW^-W4Hm!}?FFVxKAZSteTu!>}qu{<W&et*k7gjJ$5EL9nU->Y&>}^e@5U<L%>7w3*TP
xCV<i$l;a7Ty)v6Bp9W%VqMn=s)l%5oZ>bvwP<#W{uK|skD8A<j&|^JGeuYuQ$7xMUt1r=lx_J%m
z}PyQJj%dwO{Y%w?iS}O^P#|W98A&AE`;%M@;>Ks|<-Y`!`BhD4A<FV0ZyBr|iO8p&&8H6!ZG+`?
KT0rXyyfLZ}+UXe02%&SAiN^(oty!W28J%Ho>ZB=hV{C%4hU&x3*L8Fz|d*ta9VshTjf>1;(*w-X
;r;jQ4cMXVTYC^o7HeW!veq;<N{)}7U+qz`3_b47CUq1CkCrsPS0Fl4m3!`|-r+d1qVe_lIXe>=w
*rgevgYGlfdyI15d2AnjanOaveAe;<Q-*w_WoV<*Ls`J#~JL>M;b^E%k$BaqyFU=EGsfHDF4^XSd
HrD6M9Gd3oT|ZjQpXu^XH||aHMoHMbb&Cc>QrgW#*=q2KK2)|kxg)#TcUezL`e?Mc1CcRrRJQw)T
Z_7-Z2i5x7n;zZn*F9K<@iRkbXE(04Lsf)TcB^YcH*nw+sfKh&L%pK{s?0u1|sg8F^whqBw-|Ryp
2eUfLh*2$tp0~-;AZkxT77R4lOFLnmR_9&}&BV_N^s)`qaDu@&S`7Z9gD+MC$HN94Pg5m<<q(cXl
~_mz_rCimxpnb^e8;>+UqV?uOBIzx3#eZ2>W~3yE4pw3R;MO9Soa)5lkXEyF`m&GH@LS|Dn7>x`@
G%wK3&I1;Ty_;WIp-EeTw+bP%(&k2K$gpTOM4K;&<h;B!t&zYdr@TN^Jgr(1FoKTWSw}XJNVJJMs
&+1#VV>|6O_xioPOL5#b^UvBR^G(D~o&(l#YSYc9rmFOFMLlW>d29A-63SHchOA*6mA?r_Zamqdq
;eH9=D2q_Km~}NR(jcfc={UPZ-3+fWhjZ(M#&mu<nq<T)<g4ynzpFk{0x|h$$a>%HQsp!LRY?R2E
}q5oLK7kW}TkP8uODN-G%5OgZ5#2Ip(K7Y~iClyeuN>Kuw?zvl;AGpD=to>uQ2&_tGDBV01O`w@@
C2O}Zm&{tR3`117t}Bi#av9ry$W6OFEEZMXj?0Jq8N*O04rqrN`r&91ps;@_Y~_#$dEzH8m}@bOJ
(v+V9Dv}NH<dQ^!FG_w7`)n;$G<uG8^_Q9+c|Nofs$JFIKsYQKa2u_0LW?11JFBW|2)zN&8-bx%%
=qeVAVA{23Q=L8tYkLAdR#2c>xqJg=bmM(rWw>k;A<t6Nupywd9EAt?HHuq5`Pr_kt!eJBLFduN_
6$!|U){>Er;F-srBi~kuPONXhiNOhmEh!D3)@$-^3t5bZg4Q1!WVBx-^%xU)50Ln(?t)4zYo<0{!
|_brkci9F$RyPh<{IxS4*}Eur7NmghbzUd#36M@JHv-1m-J7R_E#n4T{-LY7U=G*$gnqF~Rx%?0C
Zt6?5Et7H!tX#iIfbVvhoxe#<%ZCX{_SGPU82pdjheOjPBWNK=gR$%*RhiGuq^e;D+al2w{=vS`d
No;^iGBt3(CvLDnhor8pON^}~|T4gTgefYUkq;)*3@nBL5^r+52L4*Y`w#H5dYgT37PO_`u!8PXq
cRbGqlybA2ugbnKrs+wen*D%O%euFIFB?><4aFogkEN@$=Bd2ZhDS|$=c#L&Uer@BgA7%7g70iOI
oTqtZT2`Yn>8H|c52o2RH(7V@@QVFoCKAmL!r!N#_qkU|Fmtr#Q|=#Q5jo06`_hrrRQ+czVEc*Uu
4BwVY55eG_mLfp<~xbo+MGQh|^`!pu~~nOl(@($;3oUCqZLnu30V$sR@>O$<feP^N=Vw-9t90Qwk
|Z#br8pHWh^8!e|f^!{hcgW=l7s%t40~@2$aoL}tuOZB7>Hs6T4ncHfST-u{UkM$57ZwQAdubvCb
D$ZkTGlZv~3$HwxZZMUH#_-hc_Dg(<PsImfvcaY4^6bB28)l6Z>?sNuKF?b1S%bBSL(6)DzX&h-7
o0?{lq9niNSa8eqddQ(mjfimX(`%jh+)k1U$70U*rtvHfo}UH9$7Gh2IcLm!`7Vf;a}EOcewC@rT
hC?*Wnv0{{dFWhHk)X5dcCCln$6~7UEbsre@_huo??u_Uw@5S98wO0;$VP29V-q8l4CR?IU149zP
L#jBDh-T+vW)KLqX5!qTTuR*Q*RZ2u2MH96Xi<2(y0ul}+-Si)4v$7HK}gyBxCyk?AWY++36*B+v
XRqfCLA%nn*mK*LrzLE$_`Zh9S@@v9~WzB`9GeuqH^=gIO~q%uk=g!Ofj&yx}@fv0Fkn-ZC#9D+D
%N~4(3V~necJ0#B56b%*QG=1a<aGVeaBi*$K-1szTO-J|i7Gd=@8$`E0%nJ$~%8@>4-DEmoik3)$
6XW0?E0FUsl3wsS<zzw&;C9i<7}N4#l)$^2xWwE%Ix7z^1#G`ODMXs|Ta2E{`49`Vd7i8rA|*GDi
xN7}s>UCajGLt_O)~21*9EK{RFZLAF|dM2z=&v{WFi0_5qDs2@CJ<vr7|@dP4LG;2Vqy(II73NW|
RBVJEGY{G(^#^z{K+7n>3lKjldu`t)lzQCU6*6d+>{}Nfa313tT~H>^hmy*DP<sGRcpyI{Xn&={K
jZ&jx1vzI0CE3n|#H`~t$}jrxKC4aCP{T^LnHi}h7T@Wt{NkG}}StDh)IJeK7+RlHX)Y~l)lv*fU
gwA)r01~CHRqRk(vP=L6b1Yx_?K4>2v2XnH6$HXgNQBL%r(>gu~Fdg*uiVW##^^ar|u+TFO7>wU2
;Rh@Ty1lev>3%qU^>+B<oAb+y;k&c<!`JBKhL>n<=q-2{9JHWE9{JzN8)rnM0my&8WCU&CMwGOOH
a*484}QczlT(p13Nt;CK|Jm>==H_f%eU`e51+k#b4GFZ<f%^NBv>S~+qB^P5d5TAq*+pV&@rE63F
-j!cf@=Z7h67@1>;$Kn~rBzW3ynj0Llb-WIu(`CzXe|w<_%}z3nc&?Jj-oF8%G!kUU=B*drLnv#C
4Ky!4EzQg>OYyVP}!lN}RYC{sZALOv<$qJ<y(@<WRfm&1A7Y+{t@{h-qu;K|Mp$gf$HWXVV-^i^4
Re={OuU+pPMz{7+6tMc&BHaEXfl-C}Yx=tpZ@aIrtbdP0FT*4|JxF7jdrmVsiMI3ILj^?k0zLy?y
L_3^{6^M+JW)V=RoE=i?PDEEG2#JX{2s$)3{)qG9Pc$d~$b)lLhzz$rHrwy^1_P^Wia+282K=0YX
j&>&9`^}%MYK_cwsravP#jcUZ><hGn>%38*K|NHKdXa^5b73_j{ekzMrt_jFdt`OB>#|+kNdD90~
yX)meDmSEbXuuCz%et3FN+&FN)UPoG-gEg+;zxqYqXIXL*6i+1M&n=e!o1i$diO@u(1KVK@~q>9>
m$#7JArIi(6BOJ6?v0H+Buy0PNhP+`LS3`qG)JfUf<KKX`H6Jt`8?b&q&80EI569i|CTy$%ej)1P
ENzp=yLCj;8W*<*DD;WB5sf6kx_Iu9^5ra=!JQ>RNt&$PybS+p}77>GpClij3KF~4`mtX}1*&&-v
+wQ(r(ZZM0wW^{*d^XmHm?5K`7Tro9IH7N|;MRr_mXww4zHIS&iB#dp6N=%t5Tv2eogq^bEM($^Y
7wz~R7xWsu^z)1b4j3@Sac(o#ski6aBRt28Nk!`uTL+3e1BHi>|!WJEo+FJ){B{p=AZtjnB_vwS@
F8ef$Gd%_BK1C{UuH(P92(NHnU8+1D#HyszspfRiCu2HlM?8`L2<IkpjYQ1qUT)m!8_@eQc+({+z
@SW-<**B0>9~iz!9KDswlfPBx&&&H>-m$=J6dp6~*k*oh8A8nKA8HXBNf(FeDvn-xz$m_;%!LQ7q
U<_P?ibbQraOX20}R~VXr^I$QH#|iZC5a$I&i)7&>1#ngxTdhX30x+svWjwhC^)K6Ee0YEkte7xB
FAd99H}P!}NYU4non%S@>>%Qd3!7F&<wzHpMD;XDVIha|?wJTXLJ@&)Gs;k%8<OD2YyxjUegP05p
fUU-2J1zHrY1qG&4)KItRV)D=j<JvpBNPfg%E}@(|~Nv$cc=SczmCb7xG&9*~Z*};5A{{@0NK<Dv
x=qa;{@05FSa0rz}qHg!hb2C-@7(2qt<LFDJ$`xf6hMKzh(OiK>Uly5MooDsj9pNX4$g+=S#yyRC
5^L@m{ReRlB!a9}1z@uYzYK7d2~ft{-ZaA%jisLaap_8=66)h!E^kOLQqXN=F&F*?@Dgd8|#o}9>
=3Iq?o>lAeY54n&=MC@$H4@3UbAa26YIuZ$>S5-zwXO|R7JLDjqTE@B(K^U5_weiRvf_xjsbaVp(
yg0i!dv*5w(jq{fm8pzG&@#13qH)|o&b5!pJlv+q-H=jtE4BfLa*LafyXdzEwG*HvGFsMnwNoDo8
-eSZR6FG7Es_6|1RL`?&9d@RtuL0*>uXU1ljD&b=8)5DIoz|UX+=#KCO&1AO2LPrl>_xVtrtWV@e
>v%J&KB5a84~vks>ueaSLmp2xdimSp>~{e)|dDwt|aX(=H@s&^osl-Zz3ZhIR;=PlNCi1#VbJ6ru
pQU=Y~R#V|MYLww_1=J^C^C8<|tc`nmlo9u{*OTh6h)B7RFW;0x;x>v1p%>9&>YZdrq&NR%dpjo&
%rwsvY32`SU_kb}in1lXuZ+=<xHs=R&3n&^eu=i=~WLjdhkc8@vjY{z<kzm^Ia+-JsFg6_<xs@0*
$iDJ^b9oH=PK}FXFSr1xqOwpd_$Kfv&Z6KUb-;xhK__WSJB)cc8Qzn1G7cDH@KWby$NM}u-#cu$+
iL5k*1D<AhNe1On$nBW(17@qE<$Tv8nUjj7-~&%AOfOow2!BWMgSm!Tq6+gI`Z9GzpJ?!*XtvfLR
B$Pvb9=ZYSqx@g$mU0m%L*hv^rCB+mIqO<OO}uI+#|@H3P$u7&&C6X3ZO7WYL!sVVa~SWurJDw!z
s1$G|l@uoR&b-`v|!(#a|nERhq`g5o^V8ReUoH3Oodmgpi|N5$Ol8at>tqb8GV(gNEuAwFtJ;oa2
lR)S7(KYdkUK)DF;+YR~Z<^WI1WgB8bWqgj~x1QT#lWekwJYXD5(kbPEK!y+7pQvku9;O`<ij<L+
OnUdJe(5==P%PY}KJI82$VCU~LL|VV$DFBKEUeVi&T{rO#C+dP)_?QXVE?M(AE+_JLM`=V1qb59W
O_uwCrG-!t@23RyJ$UXnf9Tq0236p-D)?8G<WcWQ)`l!A&mn`k?PZdhpIy;3<Qm*_l@W$(w$3q;h
wR%0=bYVwohj(%nVYTbe&xz;2PY~CdX^I_&UaPW7Y*>9spZ2n+f#~h-8va!V5yh8azV`g7KC{YnX
AZkOwth^Uabb-rr7Si<o=Lz7K{)5wx+$`F<48wg@B&AZ?>aNE5x|G29Yk3SJMF7z+mP?=Vdog;D3
`GI5)@%<l@m*1HB4j%6asO~}J8#1>huG7nQ>5Q-YIBs!zGO(($&h8@a6;vHU5FNoA+6imt_y?n9^
xkxKZ?n26uPMo}@A*2p|m$2W)*tiFtR&HsYMxA(Ot|Y?46Vd*E=!4G)zci*xyc3yX+9np_blhbp3
wgyk7v-EA6>=`2+G534<OpHG$7Fpni|3<BOtvpQ`VGf))bHsXF)-8UoRb(17)qpp?(Om^W+O;qjJ
w4&a+1T=j&bY~Uy9Xyj>ry}*)g)|$k)go@(en3tB52*f`PcCLpb3v_W;dRzfrni0<bYq)8vLbkw!
P-8!BVDa}pvut+q|;c{G*64xMKl<c!*_crpq5V)gmDM>X(}2ZSQ;`?GhiPM@C{2E8VdE#f76ZOgq
<%cpb6Van@a)UdgAdXG3KIinm-zm)8YtVYFSV?TjpB*%a$q1Ov~q*S<0dqV1~jGWmnVpmvSfPB}4
Z;3g1WtFQ!*_!rl^hKE_V4H;HnK%%Vds0k&fSpluESUN#CUL^%MJSN86-U7Nmnp^PWX<>5c|L0;_
cj+LiJs;Rwy_oidF+um^P8&IW41x8HZcy{ni6c=jB<&=7_Rod`|7K&f*;OKU!1)U;3I2gj=SwPf1
=kvoxQ&}fBQzie{8&b^Y+Er1-~-1xrF`=HIyV<fvk?qxMxsS-Z_c>1SWBTOw;5yEhh4kn-s<A_PA
->0p4(cFNfVSr~@((Csp{NX)VyTGFfJ6ZYezoWK!2kVgw-ZgVxb>^DoA5Cv2BoKtm5K)M1#@v>|}
NbRVT-`nwi?KRFZ}r-Fs(?^^u*B>vthMKG=SzFu<J#b@u&PhZ(fH^-@`@ocED6rGw|^0DCF*>_q!
m3hYH_XiWcX~4CsGi^3-g#55A9C3&pj|htu(Ew?6U-zZ;lJ@$1Csm8~jB3FFD1LeV+(6{dVHxNUP
$2t_zB20e_?_P7^wni7EPm#9sjB|Z*B5kM$jny;G)B-IlFVT9FY!F(5ej`b8PKS!UbWSv^}^>J6d
BU986g1|fW2{We-K8R#o;2mvP^?N%V5bF{6`R0cr9bAiczWZ=D@|I>{HsUD(01bvRthABsaOZFyz
&}6UrO|5BmIueh)Ug#9C+}#wEC4*l9*P_}=IuYHVtDnb6$Xw4mSX4k{O2ay|}6V@$Kp!WmBpc*21
ji4xCgSsru3bZgpDcT^<x$*0g{zcVney+mVeJ~-My3dNHSKj}osX6x!kTOAMYCt3s1P_$BE^c<?u
-bT?U7S;C=cf!?{RF)w@<`17561ncxr?vXz5_R|VYpWx#t>hY!l5I=Pj;h(&Qd2@pv8obi;(@tPr
04gjd|Rtqz5|fTe>=}PzHv}wMPbnC+JIa(tc?lH*`?i6*j|a%Edmz>h$gh#TAL&GSOvL@-)hspKz
=Yd^vZd031{b<?_YU1pG7`fU-OlF1v=tgVcpp03nc@K_bq$~jQxbJy(+2VsS0klgY9?GFd&eOvSe
u`0yA1^R%2^cHwB~pq{^<dr4P2$=ilwYKptm&yzl0~Ub)w*G|aR3*S1b3a&`|E!(gx%hy!PDUhwK
ib#@bXj@?9DjMJ2!p`!xc1PczZ&X$57w8*j?y1ha}WaevVK&ZwSPc0=k-&xb$thiTg;0nTFk5{$3
-q3FOM-iIqPVX<!l-w*z21JPsy>pd?T~5iD3pR5sLdQ~uU-pHe=)h+s!xrVJ;mVK{vjskIPgAo0_
xUGvl`N+1{lug6dZ?|{OcOqLB$2e56`J-F*XGJ-%AS)fQJD)Y^-VsTptZdgzj2{!`mWB1+u_T}2T
R6fTTEA6qn6Qq!ki8Wj#l@zpg^<Mfu0?ft<0+85yG}=J!#8inh=n^fMT<yl>k=K17h9jNyXetk4h
M|3~aE|QxE<qd?DCYL3^MSJVguhR!(3(MrUNt3p@;2_zd%p+6<HhfJ@s8gLr>5?rAD-47`6<jva}
#PAidYTo)Lhr6=2p1B{LjkYPO^+5?U9oZSbc0T5mi$E1<IV=ol)6$y%)d<DGrNXilP@We2N(AHb5
FG0XpKo*b4SSz$luu@^l&DP;01;byf2wOUfLQxBE`<9`7CIZ^Rkl3J{`f;;~^MFHhj1Eg~WP2rUX
|k>?w{o7T*!(Gc4DmG_f!5GTyC`1tdCCKgl5C#tHHE7OrZT{A4Xdi~_P~+`#Lwk;3~&}h0WO{@`w
-z;(`A4((ktYQOwF*cqhM1kC_-iwbc2tU6m&%rXKUUxMftxwyPBScVHo;XcA3<QY61io1c!mdX*V
uhP*jN>Ds@|>Zoq{0-|@4Z@9aa|I;}}#$8ntay<{^Cc%Wu(zA0wAyPvEa;6dtJDd`EBSz##w)xg$
BE`fjH^uaOaHcfWmnXH$X-9k8V-zyxT{iy;Z!oGkiN|vYvDALi{jpnF!*KeOFhOCq1CpC?m42Pmx
W-^?%?2(m_hGN#cLtlI${d9IqvtYx}7xq4p?0f|dz<cQa#@3x4a_j6zAFe_};*P!fi10p&+$q7Qy
gL)?;td-9d;wa?6`c)QV-$}RYM8<lUTA?_p8YS$EBS$yfg`1aAAgz?P!YSemU~F04}n&KU$-?dt<
02Qy}75S2$08!(bg#?t<HdjWBau<?Pw7009okah5mC<#D@Z()(=JR<Zk7Jup`ES7h@dy4m;d=xL8
2a=5D2~BM$+9p;L*lIuct5_T$s8JswY<)%kRs@z+Q*kT1pA`jCW~Ea~L&PcUEEbP7i^xESj6YnQ_
L;^a#zg(_Ic1SD@&K4pY0?GnAR%B)@sT?C4Y$OTmiwTgyhzc&ntF<LDt@%8!LyuHj9IO1|qpli7W
oN!=%!%S4;K&pqj<Uj3lC~j^9Cb*U*Mu+PyVc^CH_SNtZG{!L&z*wVzZClAo1a$7hALR=nPy
