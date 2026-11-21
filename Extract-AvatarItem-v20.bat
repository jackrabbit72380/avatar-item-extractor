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
timeout /t 20 >nul 2>&1
exit /b 2

:run
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto :done
if "%RC%"=="3" goto :unparsed
if "%RC%"=="4" goto :nothing
if "%RC%"=="5" goto :noreaders
if "%RC%"=="6" goto :norigged

echo.
echo   The extractor stopped with code %RC%.
echo   Nothing was deleted or moved. Run this file again to retry.
echo.
timeout /t 20 >nul 2>&1
exit /b %RC%

:noreaders
echo.
timeout /t 20 >nul 2>&1
exit /b 5

:norigged
echo.
echo   The items were extracted, but not rigged: Blender was not found.
echo.
echo   The reason is written to blender.log beside your items. Install
echo   Blender 4.x from https://www.blender.org/download/ and run this file
echo   again - it rigs every item without any other setup.
echo.
timeout /t 30 >nul 2>&1
exit /b 6

:nothing
echo.
echo   No item sources were found.
echo.
echo   A source is a closet_index.tsv, or item .bin / .asset files. This file
echo   looked only in its own folder. Put the items there and run it again.
echo.
timeout /t 20 >nul 2>&1
exit /b 4

:unparsed
echo.
echo   Error: this container does not contain Avatar Item Content.
echo   Please try another.
echo.
echo   The files found are listed above, one line per item, with the reason
echo   each one was not an avatar item.
echo.
timeout /t 20 >nul 2>&1
exit /b 3

:unpackfailed
echo.
echo   Could not unpack the code carried inside this file.
echo   The file was probably truncated while downloading.
echo.
echo   Download it again, or copy it to C:\Tools and run it from there.
echo.
timeout /t 20 >nul 2>&1
exit /b 1

:done
echo.
echo   Done. The folder is beside this file.
echo.
rem Nothing to wait for: the folder is there, so close the window.
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
    """Blender 4.x: PATH, then every place Windows installs it."""
    for name in ("blender", "blender-launcher"):
        found = shutil.which(name)
        if found:
            return found
    roots = [os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)"),
             os.path.join(os.environ.get("LOCALAPPDATA") or "", "Programs"),
             os.path.join(os.environ.get("USERPROFILE") or "", "scoop", "apps")]
    patterns = ("Blender Foundation/*/blender.exe",
                "Blender Foundation/*/blender-launcher.exe",
                "Blender/*/blender.exe",
                "Blender/blender.exe",
                "Steam/steamapps/common/Blender/blender.exe")
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        for pattern in patterns:
            found = sorted(glob.glob(os.path.join(root, *pattern.split("/"))), reverse=True)
            if found:
                return found[0]
    return None


def write_reason(out, lines):
    """Put the reason no rigging ran beside the extracted files, not only on screen."""
    if not os.path.isdir(out):
        return
    with open(os.path.join(out, "blender.log"), "w", encoding="utf-8") as handle:
        handle.write("No rigging this run.\n\n")
        for line in lines:
            handle.write(line + "\n")


def rig(cache, bat_dir, out, inside=False):
    """One rigging pass over everything that was just extracted."""
    rig_dir = os.path.join(bat_dir, "rig")
    blends = [os.path.join(rig_dir, name) for name in RIGS]
    missing = [name for name, path in zip(RIGS, blends) if not os.path.exists(path)]
    blender = find_blender()
    if not blender:
        print("")
        print("   No rigging: Blender was not found.")
        print("   Install it from https://www.blender.org/download/ and run this")
        print("   file again - it rigs every item without any other setup.")
        print("   (The reason is also written to blender.log beside your items.)")
        write_reason(out, ["Blender was not found. Tried PATH, then:",
                           "  %ProgramFiles%\\Blender Foundation\\*\\blender.exe",
                           "  %ProgramFiles(x86)%\\Blender Foundation\\*\\blender.exe",
                           "  %LOCALAPPDATA%\\Programs\\Blender Foundation\\*\\blender.exe",
                           "Install Blender 4.x from https://www.blender.org/download/",
                           "and run the .bat again."])
        return 6
    # Halo's two rig files make the biped, arms and JMS; without them the item
    # still gets the NXE rig, which travels inside this file.
    extra = []
    if missing:
        print("")
        print("   %s not found in %s" % (", ".join(missing), rig_dir))
        print("   Making the NXE rigs only - put Halo's two rig files there for")
        print("   the biped, arms and JMS as well.")
    else:
        extra = ["--rig", blends[0], "--fp", blends[1]]
    # Straight into the item's folder, so everything it makes sits together.
    target = out
    print("")
    print("   Rigging every item...")
    result = subprocess.run([blender, "-b", "--factory-startup", "--python",
                             os.path.join(cache, "rig_items.py"), "--",
                             "--items", out, "--out", target] + extra,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    status = result.returncode
    # Blender's own account of the pass, kept for when a shape comes out wrong.
    if os.path.isdir(target):
        with open(os.path.join(target, "blender.log"), "wb") as handle:
            handle.write(result.stdout or b"")
    text = (result.stdout or b"").decode("utf-8", "replace")
    for line in text.splitlines():
        if line.startswith("[rig]"):
            print("   " + line)
    if status:
        print("")
        print("   The rigging pass stopped with code %d." % status)
        print("   The extracted files are fine and are in %s" % out)
        print("   Blender's own account is in blender.log there.")
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
        # A rigging pass that could not start at all is worth a code of its
        # own, so the .bat can keep the window open and say why.
        return rig(cache, bat_dir, out, inside=os.path.abspath(out) != os.path.abspath(asked))
    return result


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-ri}3wzr}vLO0bF!J>Th)9|bz06qNm2ElE8NaTrWRj7z3`9Z_ViMpGq$E0%^V@H|y3yTekhGndZ
}+?FC=v;DSHG&OtE%hq`&N7#&*Rx(k`y<s>2j;T_24g$7RBt*Wtu%ovfE&~oZsYG?>sx-!v9_*!+
ewkTq~Hs=W!9_i+PY=1xNJos3?;8yLkAqHP44Zn$7dz?X&-C0f6lECM^Q^ncpPABrS?GyAH-__A$
81XY{c5BDhVHyFPuH0*s)T=d+{;l6ZI%#0VLF2l09KOK|%A`$r#6-#-h6c{Y#JESUv&H+hi+ud!3
X<v54xVLA$W5w;lz!y71t{e1P0pPR#cG6ldzGCI$wXc64x;}P~K4ldJq6I)M40nJPBCZFHntD9t&
KzobvD7Z|5>jeP_&KKQwXD3MKFplv!zoP-3XE3NqJP*>zbev3*Yz`$amoiDg(P9<{;cynulj0H2W
|J!v4S-Z6<16UMG@s$jo@e(-md4){!N+8lCF4i;@kA;WQ6soZ=QlKCFtA`m3p9g?55}MFVM%G`1N
bK^8Q3cxG-;^86VK{Bg_k_(uj6s@EFWR%{PMS80$*G30YN{{v#WGAfzid+Fu}!~x>DSv(<wYd*nO
j8Fgkoq3ui9W6o!H?;|vx=x3)}^@u&zoo!)+Mo6P3v5OCp9(CzN+1oK%MXV+tR5WY+%sz#^V>tcz
W-JOU={w^=ld75VhtlK0ZRE4Q|cJk&$P(bIBMv&!<RDf&HIxh27dcBw>{c_ZkBrf1dah`Qr`;UWo
oI|PmAY4pg`a7-Njyzg6f_4k~%HKZGaDvPDBLW5VxK3}OyLpxX_GEKF{mJEd1}Fe%1+x-oh<eamD
>#KI;&~ayvsnt2rpc^{GmzZFiv*yi&{dobY~e0RuWt}>iu^po>D6-;1HMl4f>Dpw<zq5V=6M!`v;
^G9ZWI8bj%M*)Fi$5*D?lumT#jisoM(DoWY=SV6F}A^$dUw>N5kBPk7<@cQ9#O@6t*mEJe*!*51e
OM`#ak5vGk3|NHEVwF-%}`Pgs97%O}=mk*Q2@rslM?f1joEd6EUU@pw^=RaP5|D-_X_m1pB6?q=9
$W3Dic=Qva6ne2D0_Tx|d?k0v!cs0&pPvZQ;b11${X3%-41}GlWtnegcNs9B*QiKva2*bvq#ItKc
Z~fr6A}`<Oh5lH~XN%#y{JJa*D6pIH+lQ0y-yEI(`2KkC;p893!C}z8@9ebCvuCf~KL6X`hvTCc$
M4mvP8TK#F#YY{%fbikb{pYv`8P+ek3Yck-<d?T`@#9vNd^;|j?T9l{IG)$kDwbd&a8gi#mA?~{T
w!ie%Ql@w6FD}9eniRCY~m50WD`K&;b2zm);5b=%;(sAkv-J$vhqb3jCNs)dE^i%5LprspktgAST
cAaXveZVPojG2Nf7USrGofIXKUTW1w%i&yn^fqwx5Cm`rh)QD2BAyyv11fcAaeKRj1(jgxp%w*4%
ff1pRwAY;#~56_xFRe_jd9e9l-J%>qveLN>R$)~97NI5xx#$Lfe2&AS}A|V2W=fPl*X6bw|2=Q!b
1UMyXkoXUuw(ucf1O9Q|<X2aC4gdx@FN*Y2GJsAN@D2!5NN|I1g9Eee;Y~99C=F+e36(b+Pp_<2w
soQ4snd#43IEOF6i<A;e&<^_UpP^-MTSJ};V1~V;TIhH4@c4YR`4(gji$=(G@OQ_$Q%H!!0P@RJ>
J_{+e?H8=k`buemKvt^7&TeOfS!zZnJy~r_o~UF33%K<vh~sW(>M~J5H#)0$;uW>J4O*UOxq@U=I
h10xk^@6QQ!S@DNwrEHy`3eF%JB79Ipmvr>ZqM|SZ^TzrJ$VJCR<gz836sbiNRLa)Yxh;}B8KYbe
XF7UU}in9bfUH^g>sHML$un1eDX|s#-Ol}`iPwZDTDNWxSg}v@O3$=Z-JxhRyX3|F&?FNejDz4Da
#XDG_gSGg!I0#&nJE&ru^n?0K7@tMe-gNe;CuTP)^*Vc=ioNdoioI^NV(O`QtFWM~<-oiJ^kHOzw
>VL^u;%ih69pi)0Gm{8Yj3A^vh6mr$XN#D9LhGr4AD1=oRzsn%%K8Vwa1m-T&<WgVij5o;#**WpI
pJQrk<*2C-lsmrYJgVUzqL0quV$eCcg2S^e3vvW((Rlz0L;ne2@WOK)bNgfBQ5EZL+@~!36&IzPA
tU=ubO`iv$?MF;MzhQ69uUB}0%kKj>HXdCY8L^Ph`2o5R}?76)eMGA@wm1Sz)x!r^^<ooDeFmLZu
oh-HuOfdj@P2{zvRrdWS0GkZ{(Flu)&1BP>f2Q8OsX(Vx%2fH=6-?ZRz(}JHiDF}lB2^o6pwy)^e
UVWA2=U4f(X%*l}=P`GxGNa!H-B#OMepypKgbE;M_F8RZcEUaQ_U*SI{O$Ui{Zt30XIAv`8&!;WK
=PqTE&)vg3oMJQfc=+@`dSX+0~mJJKcO*1OZfAV6b2@^f1*g-Zne7qi_o;$X$2nuP!l$B!jj)V;Y
3V8h6xg2t(K$}2|_I%593K<!b2gO1Z6yKh%m;*axzIk9z%@~^dlyYY`fWR?RPrScR@Z)vZkm(#_8
oZg$Zty4~s`H-@bo+bo!w+8NsCYP*w*%n0R13<Q8KV5Rn1X-MWOC87ZBD0S*-rI4GzLyB9cVHE%H
O(^)=R3>oqSWYKsyAEOFIRd<j&ba6h?ysWtq=(I5qY`GfB(g$T(f%0iJlute=pDIvbu}Ul#da!M8
fp3GQUH+3*{*zt)6O{jC9ga(&>K*4KWH8&v@tHfxgk!gPZ?$=Ew|Ng$@2xgNYBUP|0xf)^kDd<PV
+UaG*$v-UPTP<QH+Zi2&!@<gAb&z;vgYh~hGzt`uG8@X6-`&^eKKm&UMq2r+TQelXapj&P~F3qF)
V83(6Cr)5+7`qS_B?y{ZK%8$i9PRjvPY8cql8&DOBX58wp7~XXRndhiDLAf_w+{iFMtOWYXmNwhM
uboZh)x<W_SkG#}dx4tW(l&((p-#5!!Du0VSd1m^4cO&HbliseFXn@eZ1jDHGCr1asa;er2fLXl4
L!_ZU~For%?%JfdRiF{u3hIAA#VAS=pM!g?|rJ9|04RCt=0p;vStEP`|Kyf+_hT|MLK~@MB^L$zm
NoUnPPUSd>QHKh9D7g#ffHS0|B&7%`1{og7I;hjlNEc8L$HqPUj*11;T8g?$)>9Wb-%3cs>3FOZ)
-7|`{CRk@$UY(;c6PxJuz^zUc6B8zOlu~$s;PTos7?$dz{&GW8>4Z_{SQ!8O6>j#G5iRoA<ab<O#
l$QN(U_D#a3Z|mb#p#RCUl3g`RvabK$)6@8=R3w9>zr2f$%iLMUk%U;&LS#ci}=SgC9jhBfmNnN*
4AX%gRu_)(XJ>DR@5Q-h#o5f`|Eh*<G#7B54iio3q3%C1{0K-<a;ZL|_p3w3Ir?pw}I6s<>JV-&u
<C>w1AhSE2(PSG>zVZS;b7tk0rx_VxO^3aaMWAV?E%J4!$(H=nX%K=l7@N#i=mCS7Nb4+X~73c#o
n4|6&sZp2$p-Hm&Y{~qN`a-LRJ3N!C#pO7UN2NSQI0J3sl2dd1DCM4<^><));MMuoFQ?zXKi{%dF
t}B)SQI=7Z1w!wBd)kX)jk6?(U-eIZ95PzbkEFYyE_3Oq3-KnsIN4kW?!rA)7@8KU!xl5>P=h>NT
$cT8`U9(FStKW=kswgKrtcCREb@)L^?94*5z5ZYtT&lO;6rbTI}v!;DGJk&>`K?vtd*^v^16;6)_
Q?vI5`@a2L75Ptg02wS-mu3%`KvQ-Z-W9Mu=0{YcLx9Y1Qs3|-C5wlN#VXP4e^rCz&cGP+9U&1b0
PJA}Q$%X7X(_+l*;)j)OmwZeY{YW8unY2+$QaH|u^R8$?4&OvClCPyIQv$?xQ1H6?yL_2~Oo^t~x
JcJf58I;*XN{AC+>?fp}YUb-9l^`lG%~kQhFNsXG0Y|ayYtDr3Yr2c_iQ9Y$*L#u~lUu%?=ks_h7
d#C7Tcht~IiZhg|G5)QU@j^&P->CPMMc(M)({G@nxSBJz$Qb+(WQ@n#)(Eb2$RS+RNo`-tnd!fH6
!axgGT<e!;Bb7b(-NtGHONXE;%$WkNEsKIX*rP_IL3PD2r#y&R)=b$`{WKZ5q?rYoZ?U$Da_|ZQ>
kVFe+HACW_Lq7<3QySGnvJLaFpyc)gx6Z4LRp>S@qvM^wD?lFLj`$ypRAFlkV|moGJ$C}B7>LUhy
En{P`fq+LTTSF^k0hXF0ug5gO!-%7J9Knbi`b`PrZ@Km8J&NSZGU`WldUDkaBqwemo(m}cx>OKM8
-WA41E92*U)ji;i74jcf*5pNbn<ar1XVmNmy&j24id=^GNtPEN#LR~`i1KJ+fp^2pF|a8p=S<Uk7
?>82sBXI-jPtu-j~4}zg6?a@&M1Ug>;^A>KJ7HfCICO~MvdSmy}khoqUs11@F9R$ijwJJaL`P%W@
it^a~DquHp^5%(plvv_;&}iCn5tCv{qSk_QY`DzH`)VH-bg4%ThXjydlFB{v3~Cv&U=&MOWDPkQ;
$9%;HHxkA$Vh?}4yzSnz5bUl)Y2I1R~UI$s9GIG;yOLkDyMd1SV$38Fkt|5^J&aN3#;^EK=W8JY}
-TUa4`q3ETMVn<MLK(_z`86EwBfzwzT!C;jjXT$5L3oafwY|A_!hdd{LB_2baashFE#*vO39@iqY
QoUijA=am4BN<)aJ~2i9p)*ozO%7ncXeg1r)qX$UVq^ra6DPa@D?n}FcbUiYEp7`Rsa1n&G&NL>C
&@lJ&bM@vSjL#s^DP=2KBW)zgqD*Y(I<RHCJpce|Nc?#?7{5%a(8bxyj2?**{1N8h+@Ykir4zhZe
(E(a_YBMQN<&MGrDe!f`0|@5o&e;UBhd9*rkWp_;3dwUX~><xuijVSQ9ZA-Ooc7?k${zlkk4N%RB
e*bXKyfVzCJnAqby6hvC3cf<ytoK~wV_^&=s`xkHQ%7Qnb11SIV?&@2-KUp9`L1J^dP&KogF$`+I
967?+E)WSFHWR;$0(-!W{A`DS1@2Kv>=;b@>;u<s|P?-9o5R8~Wc!*nsB{Z3e(R?{g4xQpCx4~>!
>?;C*-+;vh8Y6{GXt5ie^&3II-|So%&jkoGCx<}!5FXAkpEY9Va0#<^iAv9qx6w8(-=jyt4y>jS3
;oDshRbPy+TUXF%RBz-88_ON;Woq)RGd0xiGVOBlmM}0WxN0l4i}`l8T=of5#OXcK){<Ch|%~(RB
ARZm#D;;#o2WNJvNzhdV6oYy{qWhudayCz$*k8!!{I;>_KRa&-f#+&lzbaNHamjE-G3lTnUf9DTd
=G?lAuy0yv=JFeLS*a}iamh}n|Eu*+|#)a@T2j8cs9z=+4w8>EzH-2O$i1PZ6^;3>TH^tuEA-04{
u?!$tlI7cyZD=B{H5Dx9rbf@KP1N!bqp5_ooH)v?LuAyB|L%Y!h6gq<uc6WC@Z4PskDsajU`kg(e
Kuw3##JvHQt9EJHtJ-SA^4RZ(ZCQUPgzJywRDA^uKpK1Ctl_X@RO#APdj2Zu=)MkXu-48RteL_zP
O(*W_zc@nTz~1f#p7`@Crhidvu~%e1dRYbclfh^haj;ZBH9goXeU6GOm!Bbh&gSaeZ+O1cHl4JLX
U9aV~GnrMg(j&+5oD8NYK9oY7OqxHdHp!{kpEhJj;(;8o^Etnz$2rI!J}?*AyZG59>Nb^0<S&zxN
jcSt3ECmrkCAh=IT)(5ht-vLn3<e^t_q;YJfnY}{=%T`^laqYto!8vF=$kNVVwPXzKz%a37C_hbK
}rX#3)zSIK+4&(A(j~Z3a1l$$J&-#kR>C+*5;p2&91AZB2^oSTDV1?d)|LjOfCNq$-;;T8xY4C~t
EAZ?lc1Me3XoJzZ1i@>z$k4JJud9Gxct>6q4RxWU#K36`EW$9(a19nk!p6JEYB4Y|Z|1wr@8m5sJ
4xnfGQrYbK^!kH5vc|6lSkBXB^HOhvbnDf7&o3@=5oGOV87KuPL<i3#_6oEZcpeY$teKzyWhPKZP
Zx@zqlnjW{I|4!je#^_`i#9+kgq<o3aWQX4q3BKSNzLxGt&{`R|)*r~5z0lQ9peZk)c3DMQW<sR{
n|F-d+_3`-*u_J4V>O?fb!vCVm~dM;}<cUHDl!-FyZg}fBAUbUPTb6u)n?_y(qOL1EN7Dj7|>k+~
{HzER|zWfQS)_gG?C*kJ&R-_w`Hif-0*HsI9Gq%fVZYA&aIl~A`<}3OV=8F_$C9C132Fu{-VO8t3
!UjPT#T<zuLTAm^m$QC|)CLn&%fH=YSE;cTj2m8?q}d|*KZ?r?znsgAYN#vSYv3Af2Xw6M)N`Zpy
dUFPk9YfWHdEWtN<#<aJ=IkJlOsG3Jr+{tC4e|c$A(RnHiGG*0fT)#&|pi2&F%ocT>YOxH(2{mO8
;6t{{lEErQo;uYjt1mX!cpFk1mrw&9`Xrp;=RnuP(`n+aXV4_MVMNp-&(^tggd;^?FtAwLHQ23V?
aZnhOB+^2^l!EQ0)5%72EYRsZQ#pcVdj;^01GCQ-gf7v)>2>4yh6a`MB?7*7~QqE(Z{$fu?RCbri
@+M%G@W++@3S3nn71-ra1*zk71y;P`Z_}%M*%6$S}Ay6mrnbGA+P2djrqQI3exk5$4B&1?5ToE)C
GJymV8CMM;y}@y*t`S4|+Xxno;I<JA$MD*=<7GU51M)zEPW2@01@CF<U=IP2xQ3k;iRpd^tpaF@g
F9vAgc}PfGHo+WMz|%EhWR6fZz#}EAHkUB`FArokkjm%!!aOf`UZe4lS`6{;e%}d3_Z9PfQZ;2dm
;cyVCc<wG*Skjbmb&45o9_euRrw6pQedHo)}t=p(C*6;Z2f!Ed0Bl?k5zLovDv!`da8h?T7LWUj<
#PLQnyG6BqG(J}cMid~2YvC^DLBT_<??Y`lY6ch11FeO-(s+wy9s(!+*PNj8f0Ol_5mM*UIiIeMk
G+Ef=BeK&_fcy7$KY{v^mdWV4cMlRGIb`vrje9qDJ%bAw((G(RisBb%8pg-vyUeL25qs=OQe2QNe
7=WQoK^f>~|1L5)$feZ3sjYwO)W6a79hSJhD+_8ic!+Ip()2Ag1Lbe@Z7OeV*f4r>&X$efzMPmCD
DA-p6gHe;ER5aV7PNI;e!Ns4T^k3oTJi8Qrz()bWju%7SoF&X6QS}$(xDgFfB~5X3A<pMs=%1E&%
3D?8crA59I&N5M&;%8s+Z;ybnsF1fbR)|(zMAfr~+!ND+lB76{E>uJ5z7J6q{IIVs(d1Z|#*`T2*
jvEgkC|S67hP+q`6fVQc_)IWuU3WK7Oe)WwzLvV3~5+Q1M&JW{Q2CE=t=v@+}r1uqR-LlnaXh90c
!j^!tFLsoL>$h$l&n*sw-Swe9#G`;=QM6XzG(e%QI))ZRYZU&`xOVp!`ZRl5nfYr6H2Uu6u;|m;_
Zg{27M_$YqXzc?`6NbB4!udZ-*h!sPT2#Lm<Vd5a4*H&Cmd_zAuvWX1>z~q_3n_xW5-tR0#2tK}j
M8~NvwaSW39v9wh{7KgtdTbe0CbcQF3y%58j8G1ph1|T@pu{hw#YuVEDK2oKS03P-R;q~uu#HyuC
V}~tv98N*_4c&K`XmND|YUu$#72U?6B8G;TKKgbVKBZM3T`<`DYEm#Jay6YGCUfxfrXc-osHa$`e
)-OsLNfIpR*J`$mB}Rx=|HgV5+qLr+yhcPg@w?KOy}=tc(1GX%*N4luMDL(>tqAERBK;EfMD5CFb
t>o>CV20<8#nhsbGIHs6BYEtr(?Gvu4hlFztdi3K@0Yw`jLpbJ$$@s2idG%r&JqAn$jXSO2ozXFn
`vjxO4Q-f@^F_&nmXIbgSd$!jNTNa6Tou(6XQr00Fn2dv`5v%EfE)%sttjF{S--OvdK5aas1mzmW
ic{hT-6t$M-u5^Z^s8iO_|a`f^7ORMb9LRBQ)1hj^Im552uJH#+yElXd@2#e2d40b@&qk!a?8@{Q
Jjd+SqbPo$dh<<SWDn4p{ZML%gNv2dhVj?B!<<kt!Jj#P99^>kbPeP)$CJ$7{|+)I}J@fIyjqbyF
h6l_zOI#K|I_hEu&8EFv^rT{DU=hNWz;;IL=}y{>lJr3+~z<c`uXd21O3IsV)FazY>K3)<|2ODz_
+?vvjz&V~C>V$V5Gx$QLs$XuQZ1wzqB=3Cr#9i-t|_P;}^k~`*qPkvrFjsDjUf|odRrB^BGG}u>)
N7f2nb4b7uN996&$L>K-1;n%>4lu;tPPehM)72~tD^*x)PMTdL`{TQKS)gdf;p@<T;AWO6QtyHk<
7uwMoRcyW;A2a(Lsu9_5nDk0(Df`?0?!_g;|j!CG99O^%B8@a@4tT*gs?qOpVjT*by|BDxb}mn6`
XKbvVub=Vqm_?kn`biyg;*tM=DevP@oAg8Q7)Yk~k~A2}bekBdWJFXIEhSF6PV9EK4d~EXezvLrm
uID<4bfKLrW(?64Y5VAoVA%2<LP&0Sz<c@L~7IvL~a{7gpqlXN)CQ7fZ@7#29cnS=n1FLQyL!92H
|D@{gwMPUV31jk&WmsEC*XOAex#&?MX9D|mPfT>9{3W?!FE@Ts4ia5Z5YWm7M+6NGM6-2#R0wt5#
6j*fNeW1czbaoSpm(kgKgk0)wQ2cX|B%e&(oel5q2G)mEhm25*pxx?pTCH}gyMxo4(7p<;;$eANG
Q(i6+V9$82-flfw`)t_wCjsT+c9T>*Cp1I+sIutpo*$CLUP^`9aZnAHB<%npc%cBPHi2+lcIwnJ-
}IT=70&X?mb(Iw-v+Q5YzDk_d#dRebU`gPu%fIKgu@3JFAhX)FR2NgX*i*Jc86KdsT&L^iQj*qV>
Y1!3!Yky`En%i=oq+EuwuJ^wx3>ELW~z8n_7~h=un&?(ErB2swZ_xV056amj=+5YtFu{X~i4q~r;
m>kzFVLEcS&soa_<@{Ofv6I4pT#$k@P`bu-A!~m-=m12zjScX4U3JC7fb&_l+w}=pEEFvE(MP&A|
h<r4P{GliBL2yJCf^!PR1m_OML~1xHE_D7%S&j@<z{&Eqltfnr&AkCuS8A!c1tHern?jSxNixZ2D
m0NiT%iE7I%b|G=$^J2J8qY;bwT1{$-T9DxVoM_8+KXomD65G;($~^{$9_eVrn`RTCa5Ai!A*J#(
xcT7}$PoTneS)Ow7m*^5m?2ai%3Fx#-c~EaL($|EGDKQY7zq2sm4mdVN%Q3<Q-!x@tyaR9nGMk#d
QnLDy5X72tZJH%l`ek)8Qg_I@8F#c-BRIp8uyYPVGVbh;k~dC|fKTcdP_4TS1@d|BXMqf3T`;}An
mkK#E+(9l(I<A(?qB}xew#u~a7#Z=ykYR?`E#JVmG23IK@1A{24ZO943sURfxX)!NC-F=sDqgd@2
?W`<<O_1cBWE`065UAz+s(FAHiNI}L`Rsm1`4FZS`_e*h=kV&r*#g{KykX3TazDwB$h06IMs9pmz
LF<*)iZRYMOV8Epn+_PC_dJ>8c7B$GX|~?86aMAmxtqrWid}C$M-3@<K{ti@&Y6(flxJE{O{0&8X
gP>6eb&k(o^hX(eE=J<0uD&Duj}oA+jdA<m}zxpyJr<e|>oS#%}R$md>54s{f0>|L5Q@)2YMY_dl
xQl*U{J;OPz3K67v%sdlKI$^8aiz^g}eU~OIaHxfboPwWc<piER0CN`Ar8Hb{l5RDpeUx*<Pl`x}
CVdyR7A2OP>OqWp=VWIBe+$4*WOntdHvkZVeW90-A4`-@fHM&-SrY)2Q1hpX#3l7emiCZuJ&&W<4
(}I|}qsb~5S1v0pl1c<MW&;rP(ua*#H?1N`K8BTGS+a`oo*8bA6`}3_^1)&{Lk=^XHiE@;fMH&3I
`oc`mtcYk=81l3E~b|2$R+2MC~ib#j~DZs9Q8>*L&*k|kB76o0MXzd%@Ob-H+?ff1*W?o2x2cI=_
y1xVdki?(^CXtJe$z<P=l^4DE|WA*JIuaWzI**D_X%bPFx{Ue={vG{ec)AQicpv)F7{b)<Yii9B6
#mpeU84d$3FvUJIOW-P_TL#AX3a9iUp|uk*=U2P;5pw&`Xl9WYjosQe(m{4Hd}5C%*y;vsdap{0;
RR9D+8`}g=ZfpY}7`?t^jtBkZ-Xx`t{#x%+_B@IIZuMh!kM1TGDcK++HsD8SWd=_Xp$-2>o+Aswh
@-f4j<NXj|Rw)d~RPk=*ka?ocre~Z`gqTCTK+3003SyoE3S*j>^kWjd=)E8`fH6TCxm3^R^L#>Os
nuJoeKqEQd0IiK2aS5P1;>t{y%F5S%V35Vu^!w&|8i4Wp|Bo2J;w4<DaFKtpg13o(@RAvRC(q0!=
WlWhL;RoFQ%D?Q5T)yA-_7a<lKwe_H(gncsQaCaGj{O_@YRl$7||fM>V4A&Yqbf^@Vd{mHWydL>f
j(kes;ncIR$`hpoM<@)uKI1;h&QNyjjCOAca^<;eif)LwE}V$UY1yRrmHWxk->a<+{u7`IJ`9FLJ
`dV%)I@mQ`>3-qF6$fQq$2MQnPurk$$i`#)>58C#`Yaz!Po}rJBK~_T_a!skg*Ju$FD1Bijid3Uq
s!I88M2%irmDE)lb;aYU<M=6943CH1L32|yy(T6`wMpUCbO)Z0fh?7fK>5N3wW%CK=jUxy+O=C1K
Mfbz<}RWw$iyya2DfHa_ViIZKx<;0D<s1&s@<TzLOqOA*=+<pmtlQCMD}*>Qq_`}np8}aP?bd~xp
%>FktR~do1oJ~ydE|9n<zmf)e@5*eDA1nV>0d=(nu+sEOh@Yy=YipG2UzSQMc-WRKwCbD}d=w9z7
hHzj+~`Gu$8S68voF3giLLKN{+#1B^$)VctA6E~>I`%(>ldDp~-uM#npJ=Nz*zG51IvMeiedT44r
&M7zwuB%ThCh<Hx_qms-ZLW$K86c$d&OXuhcQP2U<r#%0E{Z%!^9Ds?6D8cbH81T|?)aQ4Z@)&`W
wd5A&`FCXUEs8)ATFDIu@7+mp7*By+7>^6+0@PMU)hf=Kp;BaKVf|sf=5TdzBTMco$Dr@ntv^Wr7
9)+Jf7K6`w%x6WeC>fM?|fKUvG~FkM@ZJzmP*It#ROQDEz3x0V_P3(Zq%xnmsdPC|93m(%6?jPG`
MK(0Y{u7Z<_wfLkCL%0%&fL>zK;kae7taey!)4AFR?QKWukLt<i`Zk%#pQuLt;_qH|xTRMvQh@pZ
LInI8`5p$__JM^=z5p@Ey9%}P7CAN5TFH@wO7f(of?bVVj##Y+-dC)(yB6K^#R{3}9|*pspnT*MO
zC_Y+{BZ0va_PUOX<YID3rqtDbl(o7$VsxR=nanecEefXx<tn9c5_5@?hXLv&xv2M^+|3{rYCR=d
`aqYMVB^J&`X)}Aro|0jINb-2RS%IZ#v_XR)t9cKMF)ta%x$wIKVzc_vUOO|Hz7yL{^f|1APR!al
4*ho=p=I~wY35kW|=I$gQ>a3OehJ3KBPRa+{sajhPL=vx@u`ox(9qyHXVZujPsf(1f_`a61fBW+T
AJd)cWFa1dBlm7lwzvg$?u2R1@3K7-TLkX=)6VC522g&5C;0L>(0MNzm!8a@o+A)qbx)qz(cL{h}
$2laAQVM#4Mo$9t<<AeGahf^xQ_VoBo&-Q!)~`zQx)3oxB0hXjzXs4?MRUw;BBbWjZs%hhlqcKR#
By;Fa*1p<4SbLF#s4?`=-7x=7vjY`-3a$4HZ5>L&OLrk#8=>vfIgkDGJQ{CO6*y()L|JVtl;Y@(n
2!|yhnFoTVrr>ek{tBNTUwFd}*v|AUXZ6dGm9CQ11HQN>LuWMkF8H3BJ~Zs>Z2@mMAWneY3(LHgv
w{>LDmiKEXm-88Skmw4O=#Th9hL+=)0v+!1CS<Dtm7rEu0G+og;qQo4PpTeh|JlB5t(PnKNsmt>>
$yfay*5GJXwg>LZsFaWIUAa@|@~qpuT_7UaaqnfN;02TV?j3kZBt7%adewohSuFw6;H(7<o&Nh|X
$e#Bt7$)U1WDm{R62y6Q--;>CEb6q9f`p}=$)%J=iFCI9)f>heermkrwZguLfu+>2>|TOt)b^!@t
raa?|D!ijtjfN~|q$j7N9gEnOiRax2qzy;AHYKs0~V?}ADqLd=;1t6B9Om`|&B5HjYp@DeNvLaV|
zNJ=F>k+22lt%J!q;8pDn=@Jh4@de0Y@y5m3c}OC?_oq2DtI4)jhlu5;~Z^F&C40xU;A>#FfUf!!
rKt>r8n<Hh;{*7%O*{7mmk_06R?y;f2ncF%2K@`QxUZ*DHHUOL&Afvy4i6Rdg)=a2W)q<yH_y8Ll
_OgJXFIvL@}@qSsw;E#J7>8m;?p&{Cw*zp4o`<zD}FxZe*D|iG40C;w4M5<-o|I165ogx%BMQi+o
k6rq>?Kz1lPLnge(dKxDP6M%TdO6jjyapdmlT3V8cq3FD?0XPGoa&xL34xEE{nG8XrS9d>Gzx;hR
v<BKSyH<3E?=&NT31mYG=Dy2y|n_&^r)==GR;1_+tQpG61B<v$k8=wkXrcwV(v{1VPsJ1aZ<wcQt
*)T`Y;5t=JyBfmXET0oCRMkZuOEIArqQYRng7jd3=kj2nueJD?KF_uqTOdu&fW!`v+XULN-0E*V_
{*b3F?)2GW{;BWHkeYhxt>Zoe#{k=B=qxTejoJq+Un3IID8)&qX%0&&aW4V3Jl%E*Q9o0e)~D4o=
3!^=l}w{$tUy)lx^O2+Y|wBp2Oz6p#)tZ)shnHE>~HrVfGg!Jf?F_m9EUH@w8D&tjmPjnBQPZCgM
9##$(xJw#Zt6%Jq(vdJHpko*jL7esY4Pri&R~WA+WDE9uV4r~-wGW)27d1=0zP@0WZLjB*JMFdm}
~I2$A@2A>W@!_plksw<W^n)>EJH+r5?tC%o6A*=XibC&0GHQH1~Yhigs1rIDzK7N|C3d+bFm9Ego
H+k?Pzso394cc)BFOuRTh&cQ?AJUOrw1RhHk<Ojgb16-bf@YCXR&bm*wCV&daY$)F$k&Yfq(oE}n
fa7$&5PS0G=%FhiQ;`Z!p^fN*Nb%Yv~`K$T2eHpe?-b8oEZfVUj~l?Ig<?}0~xYN$v0U)JkR2Bkz
@3kkA)=gO777oAw?ey=0VUYu29p9>{*e-Gc?oBCkZbgP9Md?h|e<$yoiN9rc)3si(yWR1Aqg}=a|
D{9A(@C=^@U^uc)W^wd7n{!84-gJ++WTR9H$Rx=XVo7AhGleE9$<Fe6%%!jR~_WHChz1MQS6DrtL
}uO&H9$;XH-a$M0iXayh4#ARurl^kBiz;L%OQ+#kgd#)q(nxh2UVa#5lb4k%C_2GSkK$AbDazR)2
wCWD8yb?dp#4(f8=E~)@I2=*j5M>`PH@B%I_B5q&&i6?x`ePAaD?J|5$iOA0RmS51pddgb%@Xayh
N=WDtcLZ3_fRvRH4%-UqIW#v0PX|XY%A*vGQa4b!#`A3*-y|R8i)0kZ7pSBAZftHe{u3&A6kq@Ii
FrZD6&IewU>+{UGwrc`*1E)EmB_*Bd*R~*oRM`rKgXc;8sWJMghsj%i!e2zmP#A<5`|8dQ6t^xcy
V4oHJq1MW{k;jqb`goxtvXQ)bA~I-EC5(Nw`KZxV^oCS;s|F2{gy_*|9aiPO^}<blo>A$3NO8%m?
W^AwQ4;_D(xZp~3T6R72Wwa>WVIyWZ0dZy8)`8ydJ$`bOt>Z6$Lz(^CAB}&hN`wHiwFJdai%xTC5
Zv@v#j+u3rCO}%KDNMfUnl#13oJ4je)VdH7N)WHm{0raUvkEX9U+A1?K^I1ZoG&HhU4Z1$COXW=7
-LZbh$im=oPYGoN6##E)TuH%>Is~qWHS=HX9YnaA$5aZ>tMSTyg_=G&PGkBIA4<323wtWy-uAf=?
Ro-LqE8Qi<@zJslSscr23K<`s1vuQrs-&>A3t#%DM9EvaIxpAfIO^Z(bb#Ov$(0gA_Y=a(euFaQy
S>@tY4PZ{K`C6T|Z@JR!y6O>`L%YVME9GlIf6rNm>QvmIccp-0E{%b3}d>G&?VyMKo<cxl%mEHzJ
fIsN^QCogyjfsLT#OB{Q6jvTJO5+~7CA{Ji)8qXH6XV8@A`P(<AM<;KN-w$3NeSh+tg2}36a}CTs
0tEv3`0C`RWBK^*<oyR4*oVKJyc@tq!omNJ0@ElNC?=66VKA63hv)-_Trthcbvoxyw;(nsH)T!Ks
(PODt^eo!@$+AvzdCL`J9)#!SxO6j%EuUN;w0nvN0{$)>yPv7_0i9R7su~Te}GQ)ESqE8`=Me&20
#Qnx56iaaKsu@jTVNuR@|+GV_*t|OrpV}F=hA?yW`TxR}{#~AlI?0GW%}Yd+Op!95V}6VPeQyuN|
{m6ZD>gM}~HUcrVO=si9awqA6u?)tY*K6Rk2$w)&th&+M6Z%$w;DSV}b@{lHwH;fT|c-xtQnc4D;
Q2@A@4+S)SWSi*>MJe%R3E%2$&v0wFdnoq-aRF_)Swz9P*fYlDD8X1#Nfg6}dfyv<?7VE-mDCwD}
7ka7H(Uq37a?d$^Aiq<l_mz_nsQV%_L==qo$Y)a=n4Lo_YcvgGY$+BfHWtBiVv0`l9OLm3o{>DDP
U+U4bo)s+pju=o1JBd>K0q#`2p!u{zDSao@Hn1ERjw-|$BV2e9E;k1D3ln~fZ7Ro^MRN>yc>ne#q
UAzF-h3sl5IIL=0`}B{l5_$Gz}~t9k-(ya8;v)xOW$FYtNT<`IQ0}<8h4lZt)m7n<a5Xcsk3O05x
zY=m0LH?I;aY=XiNHze^RjTO>*5C`@UjC@|ru%sVA~UZn>3II8I4RH?Lp)#fsN*Ad$dhl^^SY#DM
p&=8%a(xDbGFSB`p6BqJ}ZET}RrtE9R&&ZxG$<{Z8rL^Z+IRKT9E=jWTQYI}1`j8K+?kp6h@roEU
ma*xqU-Bt(cY`b&D@m@(fCXetZb+`qrKFm?0&oHC6}Z*2&V^~;@31M=TSe@cSR7e2vuf9%E$?pt=
f<vag@EICY;3<nJ#e@TmAsIs=-UrOL94x@_?gz^GUFLC-``-xgW(Xt%o@@je6ebniogR7S!-q;N2
(dp^+whW0k>TC4Mk1qT|rn<_%a-eyaGg2ltxSqNVY`%O2HCRD|m*4R?M;~r#Z?m*3vU6-fTC1#Xi
Hk$N_mQ)NSV$;47Q~q3p00De%=dTM0f~%#a*4fC{5!1<fHDZx*e)c>K}ZB`kW@N9Ub_&bx3#ph!)
F@7A1rDielD6MzFH9ESNDDK{3)#X9G+8oG3S<zUf@R8Lnmv^+t2dKhTl)aOT~M|)N^4K49sPo%X0
>}v!Rx>Vo_E*@>t-Xcr?xkwzuQk)+_wGoS6$s}@J*Fu>d>L>~&mnK_~-~U+$Jf86!Y=j)Pj9{32&
B!~@-ka%&oD1<Jz0T3W8|{Bb^p|!%b26^@r;S)%ib+)ya3G$M^Yaj;lB_80p-4z$3ms`@i7~uU_H
RgpJMI0WpOKeV@SI?Y3LeFBv6DxL-xQVeqEt|;B+W{>fx;UcSF>9T@A(l4uhE?p4S0sq6j|*k0KY
OHh*z!{(d<{H-|V6NR#uSn()LwCK1{f!I*+>ahC^TA)w>b;!lYo1#9&ceBIGJmt9ad)-hiG{$!~2
3&+ueHKOl^S6Qh#ce|RC5qs<+nvG-&{{RH*_3n?m~Z1ec=rLXgf&7(FPg8Dvdnfh@5h&T;gAO|7&
f_+|4q<#L>(Vx2dlN;UNFAbIJuM($GdsYMseHg%M4iG<8T0ZGi$CYa2V5i6!?%BS2%(B>LICk>bb
ao}TZ(X(v9g&*lk&IUvgR**vAP1>q+IZ^Ok+8<Md@!xpXVziNkq=SH-lC5o;N$-a&)Ut$ar5e^`S
RlTgFm7s;-l(>)pZJ4%(lF<d@&6>5iNjtQ2}J~&S1+g!)kM!4Cf)A2p(ob;#lTdk4sdn)L{4VUcM
33Q9Ti;tznis(a=YfTm>FRPJa{{b4b<-uc{v4u}Ml1sa@K`8MAbzR<KdKv<)4f4(D2cT^LuxtCSC
1T+tpk3zKd;tZqo+aD_cF&KhaIMLb;?`OM8y!!k~{P;FpM2p;b+)U=}sF>53(OOxuZagAVPKmZ)Y
Mr0Y)>Qq_FdLCMJhk59Y_|1l)#q=PJYxeC-BSUa81fSaIQ9q?C`oD(cu$A3qqWCo5<~+hZ*rc;29
!eBsG}lGFiJ&YTaN}`s4OA#t6m<e$?S7Naoo{uBJ#5(4N2>aDGDqtgRsSn@h;9?wQf3JTAEpeks+
%KntYsIIuw!9i75%&kfHp-ydjWNSnUSV`vSH?*#*S(hkOBUk*O@NSVU%)<uA&W7Ov22x@8D>4rl-
#WE$hy+H*Ze|M?W2%9=)f_2|i_6Cs$rGXw8m13fS5sKywdZEVDV^zmF3%ibmttI3wjqi!Wa2)*>t
IPUO}B<Qzs<yQd>%+d$S5eDD6@^yLSdTeQ2Nn~T$QJ|^RAK@b(UN1IhJcPSShY^edqG}Y<{trm2R
PBNGR1a4hgth=ee@-I$4ynA)@3t6F|nb!SIr$frJPM712a(t)u{XttX)IXlSY<BjZ9Wy&mT@hfXC
#SEDOHiG?#~s$Z`Kn8uAC8Y+9OI(75VomSNlbu;?d)A9l+4+oAa8zr)x_Y7<d8ekEl6O<m|eh}qk
B{urNLZ}*%@Iw=!kzP<((!qVtjW7uloGDdx4SEFbDnleY?%SOpkpkbr^K5ZG|AP{zZ!ozd~lnF&B
|U-7UHC7PHcZDn+ntFvp4ZDbds-=-3m8lf_MbM@Yq(Q|3=W;!tibRo<GMuhV%^IK)Fs=VdH(w3({
QN>+jp&-yzTS~;N+ePuqRd{)No3c?DuH(ZQ!&T+&7Y?+Md1rXz;GhkX67_mZ7>MmF4TlFrgq7c>X
*Iu~Hd2?09r*LCX%&&?89tgnPN{(1|7OCQhtn@d0Nr!o0aiKuC%@@}<WO~CsnWS1%E+>b|&P-|1$
$kQFn#DOO?1};xZv*KGP#s{`=_yj3M@Vm?){3-NKy%vdRV&FfQKtj&d5}Cca!R%Ddpm{;i9}8aO(
@$O10KUL{x^N%qR6ih<?8J})?KBC+rdHbwCweld%FBk_EP}&%C53dRY?X(IjW@eZeR7smm5;pPhq
2G+II$Mas3plv0n+65Av&!uHMaI;(fib>}1$?nOtEi1Ietm-{wrPVwx3mh63FkG7mH1k(!5Y_}Mv
)ERu>G<}I0W*kR@4H5Yfa>9SSL-pd~3+~M-Wqen32qa#dmBl`h9(JZvpfMwTMX=$Tc7oloy4OE~8
hsK=o>WN#78L9eak$qID#;97KD{o7Ws?J1Ih4%&)@ZT!fuCQu2aQaYfEyAQ@OIhR@8@4FbBc3_fK
Yd%ISdy-X%4nY`EZ1jm0z5e*d1S^jpp<SZ9z*-SYdTJmo$#3M&{XQTGH0EE&AObh!Soq%x_hw6y;
upmLb+9Wzufac8;{z3*5m1`-WUgaTny9HJ=6`XSxdtRG!rpf>{kfq5C=WAFZ)oZTbD6b=91daCCk
TCCcW({hIs^0_O7dJ6@^l?Yc)oNHkBouLPT~2-q_wjYFi*MH>NqZzb%_c<+iMBA3}DHm!$)1lKWa
8J9J@7JG?W5FEaS86qbbKkkGnLC{I$;nwBkIH6PU=Q2;5T#f=RqKtXErpmZTg$x41V1CX&HT=jO%
*uQtN(9=LgAS-RG*eU0>D>@FFrztB+<9^D*(<nvGxYET%txBYF>*9n|YXR@eS51CvuxM2;jNoTp7
Kk_?D(cDXr6MKr)$tXZl93Rm*UQQ)s4N*+&KiOsm^t<eKHddk5MF*hj|zA}!t9~LxC;A)E8J-WT}
%5W1bqeXSK0RN{jYzIGfE#;cYtkYpv=fsKmkr<ice_*u+O%|+%Ko!zqe7*U1ei*<&5Z$nBuc6rRv
FB6BA~a15%aEWjctS_-t5kZ<2{&sT;UVuG1`|82EFcwTQMFLG18$#AM(lEgAF{Sf_M1m&m@P#W1n
~eMBeAtk8K2%DlIQ;niLCs412i!mdx_5jh+*$pnH!oGs?9;O{9WkecfNDIi;+dOH#8adCw$61peL
wX+B(Hkjof6LAsqTuF&2=V4rWZ97FO3rbIdE~R$T0vpT9j0!6`{J0oURA%&mK;aPqaD9={DWDOlc
GTgfCBxkdz7ROyx=gS2J{^g-9R60K0~PP$8Ofh|7Z%$bcF>nvYU0NOzQMzfB^Z3ZQUFllrFDaQ6j
;h0BlWmrHLvQe=hLZVNKuMCJ>eIyNV+4K_zFdx(0ZaE+Ts<%R+GSK*7e|RF~g|1YCc2;J`5D{a1*
_D&8&3yB2!6Y=3Zk>jTWlSo<BMCif0z{?F!{aeUk?tF%mkA7C}1e%gkIf7$qY&Mnz3Msn#ziR!^!
2l;XHofigk#Yu3vHdY;cIdyk3?Kuwje)!ZDKlT*FlpeYjDKLMq_5x~_U5Ynr14Y@yl+1gXJ>>pzh
RgY{1oQ*U3a$>~c-A2%u!bBifp1VY?ag$`m9yahuN7f<BftY=l(5;D-C`KSyVG1Q_F(00Q^c2C$v
0(BuR!C5P|HGUX;l(TbkwK4j6o_7rji&0A5m>YV<UpK*ITgD9tS+rGysVg-x2f<WRnD2u$9HeOuQ
1M5tQ_*wFy|&#sm)txSQfJW_24l8IzOMG(ZTtBCsu)h6rVztkj>62(!|(e0X{i?^MX8E=OrjAwho
p&Py!0;iw`awPPG`unP+mI>wwzgvp<jVVAdfhO645|O5+=MgCQwZca&)IGNH)BDZ9TIZgu$b3Vr$
D44^wVjK(Xegk-8qFG0fzqkuz~+?^PWNznsrNUYp8?&4)D_yIAEI5yN0GB}6JB8#c-#L|XRP@;`*
VK7g`H4)R|3p-Oq1ZFNG+X~Q9?8lV-q}fsFXyEsgU~k8|&|a|KzT*;-Do+_Z7Q0F23Q^=SXySpfJ
?r|9a4}z{NAIsVd=C|p+cPC)lF4L)<p<^@F@KaT*<je~a(=7X#%nA^&ukIw4C6Qip}I+p+&~TnX>
trjEs@dK9CSU;R~)6eMQI=6mBBH#AJ&lE>&iNPNa8c!iE*_f6(~y?eh<m{TOtx72=vw!A2GhWW3H
W8b$I?!O{y~0;t5xcu?I|FFxYT^DeqDn94^anvR+Jsrl6_e&BXXGMM|kapCpF+65hYul0zgL%lI?
M+kxa{{Ztroo|f_i8Z(o<J|}>g4gf0+L@`#eU=agDr3xsII<o(4D2sd)8qsS-iZ@8?b-N)iqt*Fc
N~@fz#Rj+LNr_Uui1LfbR{U9M$*rVGxns=7jf;kFGuIr~P?<~|%IpQ?i|!aO7;m2h#>HFTZ{Sg5c
D8C(>Z@UpN8TBXpH4h6G#%>)q;Gur@_Fy^ez(<Xv3E={uf~phAiEZ7Qk|=-VG}Dgp%!ffblavd3o
HQxT`j7a)yOT*V>ZL908CFy^t2fKhZR$J4Qt_R#cY{bDgZ3n9%Zbw64pk^MV&3>1sH9-AnIz;zC$
ii<csbju@{O0O7s^)h%oq~hO4TJuaW@|E+j}UPyKf|6Z5;Gi3JrkBEm8OQA9aVF}=3#t1+_#SsNC
M%W(G1*^{UJ^Q}kdMfI=$@hx4_H<3fUy7)%f!tunw_A!E1I$)5;EVg;l$&3QutNVF)RK@~RlLPP1
`Ui+nP9dFH0b3mn09Qkb_$W~Us;Ap*k$t1wxmh1PG7bX{30|ImTD;&ef2OkPtrTsTCl7I6BQ{#mr
xY5>@bjj_aguRCL#bhmxRc)$Vw3$rf|s+YllI!87!G(iP8aG(17<TB#)~4U#Pe0bGI&IAsFA%FMf
IqOJ*Z|6xjPSMu61JiSTpfYD&zi_7_BK^nK($H*dktv`bI#YyiVpW$zOMnLUl}HBL`c>=u8!3;1q
S%2VqsWtaHUOm&5Z=0DEFCdF;)crpjak=tJI`<hO}!X+|hcW@Zh0R=8DVf@VX6g0qQg%?xH+iPLS
hi%rR3HZw5MGo&^zRW|rhAgF`Vvo~D9j<QNQ&eWcqrbA8;7cWt6LX<~SY2*#79H|z6Cd8Ukpa=M;
q8GG+SHzVvhFHOc@+)+{jx#l0iB55)$wPy8Vywf^Nc00cgpRsi^6ax(ez5Aba^`hgIN#y{Z8_$*7
=ob^&u;|;sbGi;6uM(@1tTs(3F=a%qAGR-no&;T*;0F~>#T!iXbQ^{LuZ1fPu_sw><2`z{aG!P^$
A67L0IKz&nRt3I6<E93?pn^Ff<DPL~X;4*}+JlTrR#}S<cBHz>yEj(5C$M!U?!(_#m?|h*32uR;B
q$W$=S{Ivg6zv{lATj!B*!(lfJ+5yh-eMy;!Yt9j?!hR0bWB%|hiNZ=N?QT<9SZp~$)3?CS3RfV5
yJKfc}4F!H_hr4OC@pZi3X5q)96=3|cR5v6Yik=2_=8I78g?Q00ZFa~|mhwI|f+a|>Ao3;&h517L
1u7-mI&2YL9?|6(^5z+4!|Js5S{8cI=Aam_^hw$>qPk)*5DC-78Aw?PLmR)6y1)obD5;zByR4yOf
jFwDyIIVserT7e_+g~80<xh9s<1N@^hZKT34`?NA3q1fo0v3W+Fw-%LT&04)cSs&Vy#JhEpjNAi#
VfCqL(1)MyqLb1<@A3v65#)3A05V0H9?MtHhU($l(Jp^*AgR#WFC$Ul{?k>}Xk3&<L4D0PK^Nis;
<IYb-h`XhS8lg6Dc17T`>UUf@ilrO&c@i#SsE?h1}RO!S>%aN!FwOQj$=EkOK^45M|E+>g?0IHa|
HLTb}sxt{O9sZVyw`8No^>fGM-l>lEDARhb@oPPiQk&UK};J3x-IzdI7*l3c9sp4|=Z}L+Q_4R!t
aFwl}>8{R)a9SkBPPXUeJq4{2?xio=jg{Kd@uJY@c|(aI(9wc+I_b0#@lEc9b}t3t5qFP%dC5cpr
X^M{kVCSXlGW~Gjq*&SQT$O2!J}|emGCWtj#5XPqb5|HcmGtwr#ygtF*k`tAID8R<{aH)E>*C`Sz
=K_j#=OG?dp}p)sh-i9Y9l03JG_+z(?{k<(*S{X83FA0S$~wFjpZ4W~t^Z#9EDVw^@Wh7L@$Af9F
&kf=1*Us*+l&XPt{b_{>wWY#G4CCdB7~L`>XQ6y3;UW2Tkp3z>G3E~q?U4}u9C)+tEJONoO<@KQ3
<!d=`7j;pC4tiV}#0jcwBV}>ya_oxC?Vst$`qFDKiYC@IbqTNQux}m>z_$xY<l%}F1(pe594)H+D
6X^=l7d08(3+Qqfg!28h>Qo+;><=sP23=rUU}Xlp82BJ~&mk(6@$oD%;!=KR2cM*flZM>Ip(Z!c$
JTe(JxQtielOtA-sug)Ew~Y!pfRm{rgGy?_pMi-_))Z?OSUnvnl9f)Z2>zXOk!xn)NcS4jC8nuBR
(J}zBABUxKm8oX{U8(Mu;Oz$UU-Ld%XDhQ~~46@2!;!rg_M^HPgUw>4;k*zXTnVbWWjt=~kYzSQH
9mW^+oii@OS-cDRCyi-Oblk^6H)h4l;K@g4f0HK|qFo4Q#bNyCqt|MHNQzGG$5&~~+&Nb#qhm38*
cx4{37Ykq2}yydUay!bZ<H%j)b-revY*bL~Nr<TLK>AocOjAq!sa~%xn;A!~a0UG?aD0EpPgIR0k
4A`rsGQFzzDp!YkU@qbLxnJg6v9t=zy5%jGSk<r)3SarjtA}vwL|3#hDqR%YDp4?VbfB{dl8_BQ7
obI6JZ7!DuQesP87@zI$!j*`Mgztq)M2Rhm~V>`yCb`ig5`^wbg7-yA?qu1Med>E18Q*aNI6m^A!
a!r&&;DW6$;WbHl}Eq*07(;S=nroX*jt0j5K36BbV<xGdW7LCY4UGX1SZjAb8{pQ1Ar<+P$K1BQd
0DoG4&$1gFmsPE~B?KSe&R^4F`UdL2KyfpojN0ZOf)LrH7B+a?S9pO<xACR~fW<S9@_ZeTM542y5
aB_ppMe!40s*$tetbG8K!P5m+cY_qwEzO8X?Y>jwk+>jamO~a*&4th;lPNbiIV(g`6Ge{>Gm{z>q
XX)I^q>0HZg{S8zLmajhc2tsMTu6+*a)rmA(qX}J&SKauC_g+PLptTai2-`i5C&*_$=?L0-ygAcO
iT@u$=CbupKZtE=}jD*p1ge7vh#(a?H=n4X4jW7Hax;FHx!`U7S|7&mq67h6&!R#ZWz<?oSa%_`5
lGarDSM!#7AZ_Tt_0jG9BT8LM;a020LaTx4TlKZFfZ=D#q1}yn_vGAJRC^5W=_8MnA-F;;_b#E==
ocva$sh_?np}pM|v?#z+;l<Cf;fFij!UhTk?PrT%RPzUsJst>J9g>xO0Ji2T-G%D*zJ2if1TlYgB
dq}}eej0z1Le|SOa9JdoE&+s3<vDUm195jNxM$qOTSEw-ozc@NAN1}N@vRp=Ppb<P?Ra@*XFL^uH
=8>$`V~O&LlShhv#m4R8jtQ0k(<u#y$#{IY1Eaf+r-!>f&uPxT79)qBPRW)FH)}kc<%L8wo1!&Dd
1R_ofg>2Wt*Db&Xh>$$EbKAfNLM1dJm{#%sCQT@G~ZK3H?B`M{f{20?`pnA9G*`KeM@6QVyT`8+Q
Ued@joTAKjh}h^7Pd$3_SI1Tv)r8F|Zr!UkUuW!Zg_5Vysr)%Cco$?^?A4Y)iG6Bp5ADkJSpFO6i
*@8rxwoN^jwW3QG_;Faxpf+fWGltS1Y*BIAO`M#*Jak_m*r7>TUfpHMnT!kT>SlpoQ#q`SKtIqs3
ml71}#(V*dNn(9g*XL0fjm(UxYzHJy#RMJDk%na7Tam%6ZL(vQJ;=*3@iVAi(6kePP2vFpbdc$f3
S+#*Ii>L;wLBo_@OEeNW=C~xUCEh!%w`K!jBjY4_INha%b3~{+d4P0g=qN7eZVd=Jp9<G_;L$;rm
W3s4Ai3Po%L|tbsFCm_h)I(Qi&Gap!AcdYLW=Z70U$4tDoOrz4qA*l5n`Hc&9qK9O;)r`orslk>?
#W@ozG3_a#rM^mM}>e`?_ITZSM!6o1&IYbt|ER9Dp*+zRGxxG)QJfan-h3U{!~JZK)>8RXK7u>dv
ZU({FNXZFus{s6WbP*3E$$%=4A0u7Pq(03nsZ*T|B38Gj_1X`XAx58Q#_hj&rSutwK}PWP>(b2g^
Q(LfCxdbiwWv!k%Z+BU0GK6Bq5jwtyUS9(ZiTsd@=k9SpIbxdr>gEdbqMr9q>K%HZlKU;b273Fzf
qj0M2u(6s=D`T#vFWGoWDCP!bFy={7jMa@wAd#T2Y#vDtVQZD@tekH>c-Zd#tp4Y%&8c3mFQbxt4
QlC^dx8{WG)G6;x9+s`cK%^^gwOjywO^qIO=lYZ?a1G*?#7>!>3cQPwn@hCl8n!<<4q-%A5D>{*C
n}yB%^2FzlY!ReA;AxS_(67(dtUv18giR-<`Gl{hf=3B+13kI%BT!f(n`5mSqeG;lG~%@BPCM@B_
by31@!0s~K<g<1ptvEOFmG_*#Zpy0vWtO^B*fo?cyTI_J-nxXJ#yO~9KJq*D|*L8QRgq6H`LhHhk
-YYYWR79z=dwl30U+5fP+3v$U$BRHdOpgoVJyFEe4`|tS5s<Y2^xX*Sasq-qyuANFC0|Bdkc0ke)
{*)CT1kYeB?~>Vv7;`yT)gE)Tj?*`;_FQl>&9gqa1DaL$x?HvEt@`dJpVM7<I_%@bnKk!&JixZM<
_DbHx8xqlA;-rY58^Tz=XVyEeeS@H9}JBZNBs`jOsnF-stJA%as|#6cEhUmm}`+?FK#iTqV)P1VC
HkYhAhmA2Rp0g_}w_p;@R^&yGpMYGfIflXPMIw%)?&qVAX6>Zb%t%KUidOQRKsvLd_BRwk+%j7uj
DIjSqT#+`~KlVCN6T&W)6-br%IJ^w-5f3yLGf6HXsvAYH+#49IB=(~hgU_IsZ;MO_PeLmQE50}aj
^0lA77erFcR@=F4_#E!H{)(?EJBP7z4s{@_WxwCsZHOLO>&<HmdRqwGdr7ya0?^MD}8+rULkvyr;
dn91)z_DK@4qnMal#rZJP-o4#-X@UhNyR`}&H6U?$-T_pt~Bt&57dM)>j+<_0@qu*CU+HdKgw&qq
F3hKEYV9H>#oo~0zB<xy7n<c7M0A#$^?MCUTMLcle)I7qK?Ub8a!=S!K29LO%zJ^9k%Nlu?6UqFB
p)DE!Dxzap2rL5{smQ|Lk1Utfij8sG=-8Ir&y$&$hSjK}A7T#rcM{Un6~H@-)=|ZdU+vCB2}igD6
>xKSS~LXKAq6fkRtfV*=lJc71Cl3X>=!hdL`=>qzpMzN0q=i_AfRr;=J-<@7ak_;O4W@(E!%QsqV
^ORqGe5U74h1cU=JrDyFMsvEQ&r-AnhOlwUtc$G*NZ!%`r7&iZZm`Ur&$7yX+`kaOukNc(zjwF%Q
{-JnFy}-@LsT<ey3!N8Mc1pKx`ri06X0C3Dl5jHkV$J{uJfO|mTo3;8H}ZZS3O<m!WH84&pe+s3N
ZqM(c2cI!wa`iYGr+R|WA+_w|A3PM{F@!34x7?_u8fB*owD+QT4_K<^}shhsgo9TU6(0eD4iF}X>
yoSdKhKWttZ5jMRXlpm0ooHY*#anu7iz<YBrc=)p^cXN*bBZni`b>&FpJBONR5DatX~mIZHK6+$x
+X0zuOs1YQs+)AuT9seUL)%{8V|Rw{YK_l-twMmNv8Boi>g_DOC~5M7J{W?Vm-j>Jq}<ghOodsAE
^)mBDnioN;I&*=a_lGtjsWY?X;0jDko<HCegmf2FScyb*%{8)@Jz$cLBcq&%s=%j@0{Bx1d+4(#+
fx$r+FZm_e+o1LOZ9*&C3SMANHcS>5Q-lbzK;*F^MBqoL*vfe@vaDe+GDjn#(mQbud-_Ix<yHc_O
4KobCN{j^=k!eye_8&1bH4SB%K?5&mIj0@pG}4!>$=I@1SznvI0@rOeExHkPi-^`p=jiL&C}vZxk
h^hulr$lyvp;BIIrXZWSphYaNkl8nlq<hyR5Rn41$M+D7!*V_O5h!p43^2`3G?d4{pq5sN5PY^<K
FjtQ=vgE1r;*T%x9r6(1S(;*A8nkaWAJMpy-Hh*QZ0&oPW@VWJnuqiUx2+VXbhdgUpif;&j!dh&m
-!q{M)J}Z~mYDe*UvpyB|)Cj1MvEhW{9_qpWdfz7}q=Du8$EcP?kq6q^zyzy@C;>5wnu@hZ<rX-R
z<!8HxWYwJM)^RZ+pmRS`qolc&ibA1MZbRD%FP%k&9js7!?-cqsS*aOC+gu#a(Pn89(ad6gju1jj
?#^6I!Ar4o~}~gldhWCb_(~hYV+cVfL=UQ0c6xATut7PD5@ErWF11kt3xBLF`Wze$w>M8ATY84UE
><!Ax3xL+AFl=)BDO?uQ)%ai!5=_m1B$EAaE31@r``e&c%S&X#a+3<=97=(ufT5kB4aGq<b#T=w_
C=I31%0qVWi}`9LVU4se8L2m18c2P8cuM%j4*hdoeSB1YD8&Qh)hfdjbwZJ^?eQococtK1^lz(5<
n7u=sxKd@@~OHHnmv8h7${n1q{)KP@o&F$3SPGh=t@AaaeNIakvAarLaepVoeqQ!V@9~_rCMgY<N
gB%T*t;<bd9#0%48GuM&hUqN>sN%P%;X+a^k;KT1*(@C*QzhQ06#fXnepk8xG521m)ob}yK*+f~K
zH%w;W(aLj$#So7f^^s<;cd7rgtvnsP9BI8KG9E(5erdBkS%rB4h>}M6Jz(pD31`Br0ult)oUfJv
3f>fI5K(m2->OAqqc-o6pD7$)2%8immRh0!O@HnHSAFM^08E)5Xv>nPw_d&8bD^rVs5DNIGT{hj)
rL?fB<98yY$})8Vi(RuyB$XH9QgpmL_9s&}F5By_YQLr+{y?9;C}Te$$0PXH&D;=C$iNR5FX5Ukq
PBt;sVzU5t5_RwLMaOHR=saaKk>AK+3)oF7>V^_<1B0j6?9CgymLRBI_*RU^Z7l{BxD=MF9-%V8Z
YVS>d4UF~go4ysym1;x=?K=5wx<LJUUQap7`GY@thk=IL1DQMiQa^(p&l;CtmEb;OV!X>&-?I$>e
b!Qb!TPKr-79W}Ry3%BFLJ|fL`L}@Z4T~+bh`*k;-v%ck0$vc8Iwfi<`Ul8Rdc60ETj&%Yp!e=H=
@?_$Bk`UKL+*)s+p_L_5X3hjCp;5Hunp1=`e=5B36qH2v9fNcjGK@mhl+QS)k}67Q(`qxFr`{Nwm
>l2pLP0a!0`gUBbxABhfKs=6C7PbqX^)GAN#Xxl)#|MpbKMy!OldCS=8mFvnjrr>i-V)l#zootP7
&@yZeFctyL0e^!`Z)1Xd!NH<)FIuqUvx)fCXrRU^eB=N@JDMm$0;)y_Sx!~U9e2+-t96DM{I1it7
AD!UCcrpb6F%vCLTygy)d>1L~cXl0P-*d;mtm3BrM}<GB3Joe!Y37(YmT`AEX;QrO@Ftwg!qC57F
A|Ol{Q4ap@E_g@=kCT#yopDg8VO_DOj!Z2uYKfbtV;Ty3f*$vR9QB$Y^6UU*yEY9I_|4)qwDl2Y<
$btXDW;xT@@95vdWYe<zgVE5V2X^G_j5grUF)hW6-H!u_!fbvr^R9T~Rg{NkZwu<EGf?^e)F-jTr
sw!%aGaolXImiGhc%8@F1y<M(F-uB-%23`$umGCo&m2-Y{fo=V~0C$Mm1e<mz4ZdU4JEqIXItF9f
9i-8TId`rZ}Y`UWKBI)<g3};nd1atHU)v&JwE;*Jl9m%`}B{pDRFsio5KwTL3Ej0I5D5Yd9Zph5O
!YoE}prlb<A>0U9#4pcztCaoqhIr#iY1Pb%j;iAFcmC2k+De5EddoAHN?B~tx!0(t19JG=(Lqgg9
XWG3PEdp6wbaZ96F!Pk#vi@KZ19Hjq_;FG)v$1lxxo1r-DIzLKbenLzSlgGx6B_N9YWPRwUi!773
gOZltu;Fs~W!08wOMBNgGTYC<vf=e_yq^dtbT>^O>xu@v^DIj;WAioX*7;V$A%fVziN9tU5tcTUU
OnqFRSU%aq3^M<YbNB7lipv9sjC>kdNQ0CLW3SPOHZqhiY1G=jx+fU*1z&$q~iLG}MoeTdeAh0%p
|3!$NuEpBvqqo(CheW>XM6X!F*?h82(c-3X@)>NdmQ5C6@>a)LMskE+QZ;jX|0i+Hq8(9`p9JEoV
waCbZ&Wo}X%#R_NUio#mX{93Hzs>5^cHD|jHD~I@`^qo>VNvg~VIIncD+6AHUn>4p0xEi$S2-NWZ
h0&6Pl~xODiU?H<`RxH{1g|>%x?fy`zyy)9a}>Wu3ozLUp9_w#=v6yCIjf}&Lj0|5L?O;zJ$s7oT
1cc6QVjTG12NQAJDCiPd$v>BgVNcFKjjnd%NO3R}|6))Kyw03E_)(6?6@3RC7WG>)SQ+1mUQ#E7U
KVl<*PEw1hxC0#am>@f9jGx)Q4wn^)+YWEm>GK-G;>F|WTRmRlO7sOhiN_W9E;>bY8@@hdg?n@;{
}%hXy6I@4lR1}51;R#*Nr7If1^{lbOaSWmCj5oPWkor;G#$i$D6C5Z#$EV+(n7^I@8VREJ<wO0}`
)$Us;v0}ac6Zl}`LU#Qh+|G`ELaQ|W>|8ZhLah>0QjS-np<8@p$wO8ll&;#6;9AXaLp2N2fcD}jb
Qq7w`^0(1jyQNw)U|`IbY(m6?cdc7`i~h6rB{D?LmEdc#qsZT*5XqZ_UifjMy;JW&XQY`9<Hs4!>
-iChwEy}Wb}RWQ&&e#R^K;)wY4}74R`a!&!@Yr0xTh@_bS-fj?xE0;ZCjfw4pO7L9x5Ws?JEHufA
_%sxV+adHxTNjhixI@rekE+cVkR{>H2}E0l$ZkWt4Hqw!O?!hatZUS<Bo!bwcKFjOJM;Y#P0!X2Y
GVlWd_Fpnfc&`okrIo_)p_{5Dns?^f4I=C1@hL*roJS|h-wme=ug+pewuevvUdU2B^^TII<{t^%S
&-Ju-4ty#0*=C2LMo_~XJZyJIn#xfB>nNrUSyP)?Lpgx^5_90JDIwA$sw1)vbl)BpY8qPe`+3b#Y
Ddthc1nYc8mmZ|2<(1EWi^YnMc9pKAT^rbsnX!#`28BQdrc9kxBf!Z4T=x#AI0z3nFT8+%b*MNpp
KYPx&?`)fXdu_99F|MMD>+ni*kon#ur$_flKrO9d*D#|BFBBg_1JH22IXIRo7VEX39!%`_POd;*u
?~%hG1<^tH-#SteW$gWYzUPN3CfdL({jt(J~vqF^|#A9Wd;RQw}J7h+?ca%oBE#zB3y(=V_gB&}V
=_kiVOzv<+K1x8$b`l?@L!i0L|t1zBrs*~S}JoChFQ2NKujNpLKTBF5e8tN7rQmR3;Et?;fxuz>t
$?Abxqw+po+oy%*dg(MjPW?bz>^fF$R;nep4zwzEvZVKJ5UP-bFwCbZMpT6dsIye&-492aWh)wv7
a|S9iW9`$XO((`0XIrDrDkc1hP_jwGS;YE+xM%6&(!%5Z21)Lj<lg?5R%D5I>K|5KGFas&JLGRAw
A;Dgxvq(T$QUdJHv@GOLlXW=v$J=NCGdwjGj)WY_L?xoT3}nfX@t|7n}nHubrcsVZVMS$PyYi{Sm
Fs2mOjK@%8aoVZmT!CR4tUR2_<fCiL2vex-@6o&S`LaA=A9nz*QHQJsmbN?efX7S8&e_C>9&GaJf
RE>o-OV4;w@1Hsdv(_R6V5-_qW0LF<g_ge{}2@oPX8=71aQ9fN|s4n(M+C=@(?nr+l&xBHUZaKIE
hk!Y@KdRu|%H*;@KRD<JCNbuWDd>eZORqVw``qv_E9RV$^Lm_L#^WN41eXT`dNUZ98Q;<Z{cz(9T
@UbW0~UH{dDPJ3Gx5Z|2>f~3tYBtsHr}F%BU!1(UfS?<Ks?A`z=%H>po=wjNZKow1?pAjA-P`TQf
xK0FckK5xz*<&DO(uZx{Q^Z=2;_{lHQQBCXUm~38wA&_)QT&%~5NJw44kZE|;8`oR<yDaAs+o_al
0Eg!*bs>`CzsbR_klC9kt|LV-18NmN{6BjipB@D75%rOyHiHjHV^l<|BPbh;cvp6y*Y4h?MIB1r;
cJTTY@y|_}o6FAQRv*tHfi!qH;1TC2B(Sm$X%Mm}iPqH+|vEr$Dy%@tNp?f5)0c_0qhS?ToxAB;s
0kNFN62}z7>rl7v$orD!<yktH$ZjxdC?oM7L1IHvgcc%r7YVc5*`qi^cKDk+I<;Z1p_Emm*RcFRz
q2{U!(pET7NsU)bcy*raIUD0vKJB>=RAA){^<4b;KRv3jsXXI-Tl3T^X&D>o5Aa&)8{{6h>`Q`&5
y4K&wn_2{{g@5?(u_n?@wMIz5iwK>iEs~r$6AUeSY!b`1#v6FYH&{oyX@Hd_6sS_6iz1dU<^M3q0
Q2InRFh@#RZs?B{1Er&zKB;NQJJK7D_Dj88xO^7`4^R|KM6z92AC0m{EVI(buh-sw_{(1FV1qgN;
2zd3$kJ>RF5dG+@B-%fvdcRV<G^AnVM!G0;_<DZV-KRY@-c^#1KUp^OzJYD7EAKyHG`x-j^;RC&+
{rc|hhm+Hjw{Hd?UcIH3!(N+%F!eAF%^v)Z;cwvkE<E3Z?~mbo2c!9PA7c!N<DXC89}T42p&8hzL
qA>m>Cw*){p`}u9{udo4}~CdkF&=O{OPpi|Bn3MmH&J4|Bn2>EC27||3;vv!Q~<yj|S7cNO2zxkl
P6r<x`<SFf{tNI3Ob?NEzU=!(+85esYV}MR=B2XBEA8Qi=LPZak%zlh)2i@!nodd3yioQP8y;@?8
F^8l8P7e#=>Up|k>L2<`%dp>~2NPq>Pc@s%Vlr8Kbc<Jr*%+>-w3<g&wYToi%IXAmBfYa<jYV`>z
ISrWrcSs}Jwe|Xm9xSHbhj#gzW=?;)3J}Is!1SJ~&X;Q+mIq)<}vvfWfgcw4@PSeE3pyR7nnoSof
lfCl_hH9@IJ%t{@RA5X{|I1=P0oV*jGVBUk-%=<g>WdRcMz{8aeG_%RT!qgiIlHO1XR4m7V^ZL%n
n9J}%k;^jEWHVgC&8FHDaMAvI0bSLvPtS)9(+n>xytj#H#@K(E&n*0?l{mzsar|Wkpl0ak%l-BJp
Fh@M7<h$*2Er`VoJ=}rug|BmByX!%eI=sa!JfU{GFArbpRgPM+Z^xF95g-K|=S@zXH0)!s=m<cK0
48V6l)VitK3FwMe$j=TtfHBrDJqp7A}yg67!oZt#B2f$@aP^*uObOk-rWGEI_?b!{MDO%d@tx{Pw
EoG0!iJ$)*Z!{F_ur8K!Ut$TK8*(1zM(q)ddvMf(z8aABx<{=k%k#1$bWO3A()Vo`SaWt*&TUiJi
wEIqG@3w;aH!!GTIg#Gn)b+$<dCVr4X!Ls1;-jPN+D(f)aA9wHDE$<RXYi@w2sygPqp8Gp1;f$B5
@Mn^jL$~^U_5<VXT?V?_|;}!B7;*ifnx+tKsaLH9iB9^h2I(qPao_)v{S*Dzhcv38Q1o7jW$2b4G
g_QbRwPm2Y|DO<WeR)`nQb4Ueol#+ZF0=%}UnT5t!(C(}H1~LEVcgj>1z5OXEBLX=oAzivpL-!w)
>}e(gC=-LKn(V~WATY+pzvfh}?*0(bk_%wot)l#q*UZVs79w;I1V<O1$Hrjd$@*t>Hwouf6V&N`{
aNgP;Z%9!s#=llW6&7))>7g@km5eAct*J5zx4cM4MgR+oICRPE6pku(M#ExK2w>~nGa#+SY8A&-T
BfK-Up<a$nmjyMa<pdi{w##_2ZhwL~M1-0+4dK3&*G5@5Ml9P1x_pF^*<xbx_&fx(-}j`C$4#LN)
7T@wBNGpn@E=nKN<*K0!!}OhD--~7k1L{ZKWenzZeW?G#w^s46DzZ+?}B7d4qG)C)!IrURl%N9B*
SHm)d~%*%9QHG6Dn`ZRXMQ|wd1i;?KrVJ%#{N;4Fifh5;^N|?GA+jFu@Tig149XSZ!!J6dYuWkei
~H%w@Q*O_0RzKVb&WgXium1H)+pbavNbwnpnlU@15LH$ilTtA}5UtmTfOS>E%bGX@B@F&ZbUSv@8
yqXp<sjSIh3riZILs$y0wwOmeHrnYG*s}OQUyRjsMQ#gtUveLRTMl9HPSep&4+()swi`Epyj%;3B
(HLW}^;OInske|6^fBSrPakf2LA0>53+RJrMdDg##r)L}zR$(5)l0Ae5ng$I)RSRpw?c|5ya_yAU
M2%#U@ClykGFBGQkcgkE+?vnRKXNzV>sK|w4cZ9EzEqyS>NDIF8n^@4*Pr=j{?m?6aV4z%~pri0i
(Fk7sP7K`YW|f4N-Itkj6A5{Oo|~rz<qW@ByKo9GX?|YqzsbZ?XVsZYp;qTsh$E(2+-eg`uGK%{8
W__tLV&^rmCR=#00p6<yf{QUf3GDD&vf=t5=XOV4u&6<vLySx;-yUBN{wgJxRqGwTM{Mx}>*mouO
XkqYwi+>+BUNJ0`W)uS7v61rdh*BB}lm&m;UsAw(cnAZ?*sd%y4-U8&Ak<@h=&c6ZAA7X`lA8=-3
VG}Tuh+@yx#sOu(^kIieC=07sCXJwSTjJsc&Y1(Jyz1FT6+DPn2O!W??pGr3st-KCs<%PJ7`ZnyF
2H!4US~9e3K;aGa&Kd4s0J8cLFqr~RvxzgeIvMacKp4f`B)-ax5<&(D0vD!w^g+5!b7|e;MqN%0=
E?+evji;-Tj|<`I`<W$^0fC86%*Z!-47>_5Ra;toOGZRE0*+3_e+{;+=`B>ba$pb$<i37($g*p->
DBbx#Qt-O{z=`Ep+}i`{nQQ;!Pv)A>WQt%)p$f!c}u2b`+sKj^#%l~k#$vT9WAAX0B&pfidz!PY1
6>U@g@5_gZ-BKbW<GM$-Lv#glA$BPM=BB!UHDnqsuk7}G%%ePMyb#dQwN-ur0Smu#fA)+qpn5KIL
QtwNR({3btx|!q79c<RQUF=-9{h#jL<IQ^4shPS@-7i`>OIhuu5#8wDG84DaMlP_c`{wD|nkGx?A
$m1pLWF=wrVGu~5x-N>%3+X?pH+4oHW}&bG;28dWNRTA%D5Gb`obnYY?(eHV%akJ@t@y3ljsSgz2
m%mcq1w{9x84<S*UQNUW&~DouKTBR!~OW3r=#&1}qp<HJ&XSLI6sWjfNPfV5oEKny?RXW<=V+5<i
%nb)mHYK+s?3S^hnA>>Ii;7B>0=_n=6UkDhQOWF$olAorglrrgKF`FJUzOvrkyqPDCsz176qHm_*
1l-uUY`W4hhN^ePlVc<dqfutm(Pi|lCvdM1ANtZTP@>Zweq0}kXTl85i3)J4a=^k2ID4XSX8F;sx
UBnE;IT|PqJ*-S3ca2iK8b&_bCX<b&Dq7#<0Pk9?c`57LqbM&nxf@T)F8M=qx?FwVe}hvYsMTV>*
`2m-cK%X-G3A54S7Yw}+lFQRqCuFFK4T9rp?<5WWXm_MGL^_UNoNAGT!w0V9b-e`@W}?ueAu*h*%
Je>&#&8TwHAuoSHic!JRjw%mLXein?Rct!PIv#X~28xT~IadiV(PB{jaKGpDFiQCR;d%VO5CyYgL
h3Sy@IIb=_8jU{wLsLAPG?Z^7b&_5IPbnbG*528&n7;T2#mx~y0d%*jx(u4@EUL%cQ4>?@aAz^;p
735VXtl8-uwHt<e2MOYG3K3;6TwmyofVEILtjjpXxoKaG>U+?C(Lm}Z!i8Gv0a(C}bYErI6Q@`LU
Lsmy2)pMa`uFWRHI}r$DgIQ1*WQuub?fc_{i&aO=N`=ts(4&>flbyp8@71TQTMAR`tSXD6x)`UQL
nqhK!q1xn-7@YJ!?16|38!jeXwzAXsBR-Zmcm=XYl~Ph+R$uN5&BLAS4iu0qqRG$O<{EBEe@2*sa
6+PXKhLq3kX9-n;Y!yjvvlW|KRiBbp3D+Ffi=~fYwCQ_3mD_^GBRCayM94G9a7`P~UavJ)FFZgs$
_{;5+K>-AnjoS&tc0$-guYb)_0s&^<t{8tYh}Kj+XiPw)EPmi$>+{^`oSN!}<4o42mffGA44nkZW
UpOlBn+Tb+EZl1ZUC!WnF#0`jyd84vE28^|+Ys%K&+k0md0P4}Nsxlwmlq{VE;je+mn`6!Fo6rt@
_4{jCo66Zl=h2riHqsHfZ_bhg{kbR#4&FwjML>{OQnJb%ZLh{squ<envknloS4|xwOz1VH>|)juJ
$-840Qn}9Dy=^txkvi$P7aj%I?M(L@XjWu@2u0PT=BKlqt3svcioM8*Im)O?w{SeVqM^((uG7XBH
Bvt@uflO=W~XyF4lApMK#NJglmDQ-K{gOt}}n3ZedSKCBoOqP&VM8*WV~kB##M$Lxqm$#DJPXFQV
Jg=yL{W0baGqMOgYQ;DnOgyA1?{6<y&WepcHhJGRkobFbgqn-s@wGx@B2GFe6J)Hz@sr#9VuYN|>
<SJWd&$Xl~tlPFWs8?uIR)cz(Iar<zMlFC)cnEl@10F^0vT4`nd;pqdw-@fDk<yjJFm&p=y8}QY{
+C%d<J#4Ao{ERu1!Tk1FYrOFYL|49U1jTF^99ru5W}TkP>hqHz-Gt~NgZA6{a?DTvwuX=P@Un=g7
kU6^Fq(_a>Jx^qXI;%{+Pw5{8!)=%<gcMTJU8ivbMrOx@)>io`Fx~n=3)arfv1Uj*R;0V|1TzPmD
R5yS8YapebSp<bFIX`LXGgJsLlAUb<@MgH=xzByQ9!ng`<^GJQ*3NXWN0R&0cfMVa#3IH)pl@|7F
S_Q<w9k7WIiCI1HMr=L+w5vEWm$j^=apR&qq4t5_^aP-@SnI(-n<_5^CKpg^;7`3B7B%KN@bciAR
Fou#H>LqORM3(w@&C~p1aXT7er2HanR&hAQhhNr5pZl&8-)9P)dQ-Wd*>iP3`(^hh8!O6K6wy$Q@
r8$M&;9xj~FWydhD}UC%Dh%>`HSI(9x1rjFKSN@Yp~C%&Y)L(vZ{**T!^MoP0<6p43Lz=)x;;bn#
3Q8hXawVxp4GWJ0zet<sOIolm4ynEQ_wu$A0MpPp)$tRXVGeHTzpyJLF`e0({D9~{s_&%E+SJK-U
tekE>#xant?Q>mro9LV^8$Fuk?pOe<@X^sRoP2{POH6A|mM-)RXO?e(4+}R70ZEaNL^bGVYzv9U`
scPK^hXUZCAN0|f~SU~G+z4A!j5zMW)O!GmkUVeojI4JhRd2;QBEF->0?)ocf(S}t2V>t`30Y6BT
$=CO2D);yKBrQuPN-g)YprWf_p%OFG5o!~oL4iDD|YpXpDOt7Zo!A4MBPlXy=ERW`;%1Ka3Iuz!)
oNv~7?6uzF05_#k8CyCPp^iyaj^VI<-)Y0Y$cneZW_PY>V$lym$F7k)NuppHr!&fwDbB>ErJYJAI
&;#|SH_y<Qb-SQp3gap&0-P~1*dz+1~p0{<*0b1?C8i;5Q>Y@V0cMsuFTQWjVN=_A;o)Za2t^s8M
8Dei^`}!dfax~j*Z^-q3TA<vI(_n+mUrvuUyD(LY9+?yM718@}X_Fp(FTf5ZWpO%OI$-0)}^xN_r
ayQ_QhIVaM)ry)x2yHPe<eQ_V!%-c6=)q+x7onn_AYe#^1oX6f~S1DqNW;ohg$Djhm<G-cZ3BFI&
u`yb+Q9y~t|ijT=Sndh8{{N=kKo=rFi-1|kQ6B<7oCzL@m{PovM`Pgit)#>#N4PW8QbUDAtDgK`B
4m`yegTMY7wK$|42F1YuePygT>`0E$h*WQY;RAXR6gTNqf~$2NH!m@-C$yYS+nry3J<s5SFltz!x
33BiX8rmro8&jA$qeHx(s+V*Ic9q#)7N4+OQ&-Q$ul|6D0(&K2nPsy(hv&geV@e0O)rCEe%0i_cP
B8$?=a}#B$-`H3d)osCSND{B$=Zn@D<w8rbMPFH9Pj2veReu7^AP^4#8OAH<ZOapMB&AaGb~xBi*
%Vy76hyy1Kllw>Vedut9X|w@E>fL^;wYt=k((YDm!%DR5#O{Br?vK1R|DUZ<P{a!MI!0O1mj5{Pl
aF{fggO_7%Zwx5LZhQhZPW0lj)7YXGb=5VhZ7myNh(W=HDlZ?Sq<Zu-m_L~CMj&dS%v{wwQAbIT(
?UPIb;1O{L<_2%jR6y}mg%dx|ek{u5DH<Cu>v6Ez<o3!P(QG0bqG(slF`)TPnq29Pz*BBoMV~dBz
+s$k!7sulDR6-=a0LO_buyx_S>A+YQXgS;_#>XuZ;oCcUzqXx(g}qxq>#Mo3kaJx`U?g$kdK@#r~
JAs3<#Ig<#|Tajn%PW5y-3mcY$fMG71X$Q!<?AB!+SbE8a#JQE>tDHsgqlv=J8>#y0}Fqs<>V8ws
Ly5`^tmyVu@12qt7AkMXJ>U;xfI=(G-c@boIZUXYDFA;z8p0XQ(`h{O1ea=5`-p+`&`R`rLYS8oS
DzBxJlFnD+Te()Oo-|&8|4Xp)_f?f++<evYX9Ca><YQV{m&lq<bxJMP4B6>jSaDpE(2IZBc0mbB<
WGj!G5L$h4{POMl*Mnzo-yBm&K6T&|r3t3V_%<y#hZH|4rfHT`9(2qnS%T_;@;m2gYS@s+!EhYkr
o*uXY#c16K(qkG?5EKCr1B8AT?OvU3wP#)JM+Pv`QeU{a$euqJs8I0E4QQh+|#E@-C3pXtgI`CKB
MTHpO4k?rM4&gQ|xyF3~)VX%G+(X4}xTr0(yUg`#c#gI9iINDnM`{qTPqT9ltt0efwsBfF<Y)vn8
Xb6&$0>2Zs<yxeicCqDuFT07%`Z1`txUpUP)<QD4&bV$e~5xTK)8v|X45B=?aAu;DQIQ(hq35eKJ
D`gnJPzmcx6pC6tG;~XgTeJgm0yQE0VY=^CO=U^8Q7rH<AueT>}P7SmTySuv$ECT=V@BZ#?w-Ge)
!NI=y!v5Q#zaZiU4-~r}w!aci$Aa^?-NC<mJNu98tNXxoOEAr^fz$I2>tOfbGlwPOZrCx49qjB&|
2lg+o59&t3uaDFZ~w7ObEmiAxb}Q-b~_k}l*YBUyBQqu1Py!EJbyul4!nTAphu6rGfflB9Xi+$5f
w)7@f7V6=5#ubcNtLcV8bQrD3q1~>{GqRdyl0@?QUm7KwY~>Jhj~&1*p5b=^pFZJ(Bm`wqSK{x4R
)Ah1OE>D<)~T>{9dVW@*pq)0a=ves!7vl^(Yhpw6aUQpnv=gW(dL-s6s7Wp~qg(&$Y~)amZFWuDZ
GZ%iQ-e)A|g?H*4HoDwF&ZvaT)cZav?*YrtYc!z6#MW=fHDR1w!g)(*b_cjEjki5%?^mu2Fhqo)k
>ptFa@w&S<r1s+jhP1CCZHSuPJqyy;Ou0hxF3-!?4DY}J^%diLY=ioW0ruLO$DyO?v7#)!jzWYDa
jMs`A?<he1=7AiI_PZ(scS*n**TDj>Kv#(ZAe;r3eUS-^J|8;<AC~#@$K56zGi?5(|gqR?(RMjzQ
?^DpHZFNP5ZR(0D8<A)!Px4qq8Y(=^Z$bx;=)}5z?}==?T+&Y(t{+03dbuWSaJSoAQ@!8&bDR6TZ
K{_xLj>e5d2i6G1xIZGZ04?Q|_jRV3)_Z^&otC@dFl@XN7aXUB!~#b~gz>w@}XJlNTDKz#)w>^q>
o0uv4@bM?ij@Yn|R6}YggF`Z^)uf5Z8P+`NF+SQ1Dz<~b0?w+){Z6n#gf^y1LWDFssuB@5mRvbs`
^*+aO`Pkh&hJ}JiNP-O#3_+TrUH<Q{&pB|Al$`fvU8#rwW_o6Nx@UTN`rxyiLkZ^xZZT(u&>u6TU
avw3=Lh2HObPvz3Y>k<d#^(Wr-wpPLO*3T?w>Np9P{?xJ2^g(W6qS!Pg#=s3WO__pPmV%`(s?G{P
bKv-5=#j<)^&MeGSf)%Fp;%e}AN(E0LeE-r|He@w?;v+#EiSSpjnL_?{>~S0d-7_Wb1Z?4B4uH^<
LYW*1q4?~d?uC303@ot>WZ3fz;$<g9<-VgKA5KZTy|k8maOGbX36!MHhp{zW=<f0QecpFI|Sxj)X
8$j^ny?~U~Ddq!nTSvzjiIKlM56t_Q_rNiGJpsrQ5w>A$w--G;we$ArMJtB>6;1&<*vY;&RzOb0P
$*QjMqF4qU(u#Jy+jX%Hxm;``{26I?%4nW$+*GJ|2jrA1F5jn^lvYbg`V+Zlf>LNwl-{nQa+1zdc
*^sX@=ckVc{cyh0jLdiK4$4A&XaArG^G=${1HvCpoXnbEJ`U6p-vg&EOqb);PK+;=Woq*GvY+7TL
^8V<1t-xFb=bMU{%E09lA2Hd32rpxea=5`1J?;`~!b)x_)k52eg|f1TS4UElh;E_?Q|bbpHMT=pw
+(w>Il-*RM$dRZy9YT|hg?0(J9l3@XiSOj`71A?a2~yPlProK$XNG4o`$+EQjXe6dQhoGv>{7oNG
H<U~4?8>YoXZyQndzQW5=Aw9xvROvT?9y()q6m;yZTc`8K#>Hm0dw?DOk8)Ml!MiqMJ3hR3yA`CF
jH&q0ZJ*W{9%5)ehS`j<Gcooi{(~M5o89ax=%FzigOt2G)Q4Ki9eg>WE{r27K9sloINniVU1Cbw`
5X}72jO(aC08{2J1sQjH9!|~rUcFTk~17|F?z$rs7-nfg8~x@wzk=BgN)TM3&L>7y&u;i9BLN^)%
>|t1IDXl3D8P*GQI6+y)gKYZijg?yPTqF3XmuoCDAf)L>TBsp52Hv-7(<&QfT!H>-*WRSrwXB2nV
fRzy9>ki>G$|%8Toczcman5hY*h*-X9JH80LgX}+lqt(&^>B+Kj4L==Gs3T?Lq27#X={Si_Bq1~e
+OlkWl=nuw-3w}Z2k)<RXSn5(KsT(ozuT8`I`vYT8z*m{rA9()~x*C$Tfcr$rA_rXRI<;4<_8-)^
qy*1sb%|Bpb36Kody+zwq`x#AYo;e|BlMCP6o=yFGr}yaL&DFffgCrIq?Irv0}Tl~G&cT;<Kka5C
jQBtt1bnMw-JIJ9S_E1uW1TnUa>Fa_ru`0lKhSPJ>;gy#KL6Ath6Oq9M>cGdJXh<H^8WGX@EZ7se
zg;Yqglh3#TS5Q6rPUo`v=<CNZ2OP#wXHj5RB)ma#P{yJbw0is1@n(9Mi}X0H<5WVXnpxXYCtTzk
poUJZW@bI~pn<9<nb+QVRzfLt>rH<@yX6zPj~PpCqW(uU0o0@}+Z#{3KIu6b*ote3P!uvFDxCW#G
VLSy``nO4)=tfc6KepGNlqp~eon;7{n&n}k<S_4FAcqrpQk!?uxNExmrAGb*~J#aHk;2V|RaK9j{
9^4}6he_M5MWhqSbjoR#9kGi`upKjnGjc)uo32;1B<A0{Q6N1#^FuaO4xEUbn-HDQwp(y7;KQY0r
#WZaAzY};QZFLYN2M(Bk(rV`R7f*AH4W(8hsQ{ryMRt#|MKMRyVn;rW|yuwwY)CkG^m}*(O3U7Hg
~0t*_h0+Asc0VF5_vo^x2FBV%eS81cj|l0w*6kys^3K>&D2$UX`@*rnw!-<Apo-a3pW@^CIw}V5e
m5vP0X=$CRg@nHDzDyJV@iqaSj{dg6aBW`ySTyvn3DXSwY==Z!Wy<H$>#z!Na^^QF^E>={7({Kc`
2zI<OT3a>mvcEK=Pc5)G#>QcZF`Y+$_mm4ulRr?GB2-pu6c``|%h3{}&P_#@JmE7W$nMSDfq&R>^
<?jv;E~NImp4j&g<KUvWXQzfuG;b0(5vv8QYl5kn$+3YhCvM+0E8U8yNcHTJ!p4y?jNBvGOEf2Br
>Iq@suwUx$zK*h0w_R4V-`6)gd#x`$U(3w;v48zOr~HUr!V+Kx?p29wyDKqsX|lM7lYp9Hl<+3TN
AD~VE`g)!nAMT>`Ru@v#7SOLtkU=Ne6dX9Ndt3X1$29*T5^kA&y|6n`Ak4-YF-5<bdnJ$X!$$7TG
F#s(Y1eFN{**DiBj{SOu{MICr9T)&Aw;%|Ac_b18}k4XfZo*u)>gWcjqCw2OAjb9O&ik?E=@f8)x
+>_H?7v+Ep1aFTe$_&%Fpd|o<}lCAVy21krZ3m!fLR((3;LY5G*v6x?W_)kdEgyXzGO8|YU3p%_F
NkQzScH(bd%%9513`h`>n&f#Wp{*MT;OC1s7cboNS<Bv9>xryoW|jmva!|#4>`-+WHvwnn)&bBII
gl+~9n^-QMv%Iu^#=KUH0R*Vbg*&X(<o~n&HQ2+JHOs);7U9yVa7LUc73y|NYAdr1{&0FkJbyZC*
{qM%%{~T^atx+fFj~2EKD}nCItF(f^>x|($Ob|fHtabMf_L>N4Na-6MT(=H-%lha493JSW+8{p0F
Dn{VnKxV!dIPEOS8$o+LR&DlHsaa(0|u6~$C_X{5i6+)<0ekwZ%$@h!947|v!n&Qsf`=((u-O#X-
&uVHQlE5glif1=I4gPfe+0>wly2K#X9K5UuI`GvB8Sp&vCpAzUApXx%j5#<d~@50sDE>vgB^<@xD
8KUgjSst@T6L3)t;{>28)g!Us+n~wFz8ic;4RE0_=%+{O&OOVf@ht^8!VaSniyC(ue#D(?`i6jyq
n-t|wV?VtK=t>4vXc>7M10B?9dBMjt?NvNnN#eDV6=x}wrHSTKoDUr6zv)IguiX=w-)WKogbYFQ^
g_4XuX&wHrj&7LM1v1t(apTM*S<7ZOCb&!xQ>2I=QOtYYv6;oy8$@9!k%;f8G)1h+HZ-wuT(rU~h
tL;2PuLl^s34Rh=ryf5W(I&~k#x$dEMlq?p#4Y+UahT@*Sh=Dt|!AaG7iM}z2}2}x(Khj-T(q?Ws
e+ZmY(V@heRD*rey0G~iui){y1L31tOz4wnz3UYulU=mETD@rGi0w2PkI$F_nnTjIi(rov48|t4u
29wc&LE7z(xIiZzP8a9{G)b8`!oZnW)zgxr!;r6MSPd<#!C@N9KTu<cg(CB24IARr6?&xLUvcSrT
$hm=RpCM`EKu_bOIIzpJoWKMrPj1qb*LY>6qz<F_%L-kau3AA`&QcN+Qt=M$TPlFpc9G5_N#miN8
Gd=9#^<V@EUB0$?<|JxlXcqx$^uBivYx$JQwv39LZEpLO(+z8vKM51pQq((5@2nAd`(6y#@312;D
%Z3UO9ITS-Mq3H4%<FXVu1%Ros0*EUM1GPN9!SzDM=(93j%DJ9SiaGFinF^9p;#VK)FY)bYHyao}
D&qO7%E_b^W7Fn+64MK&pP_!&d(io+G83s9YyQ78V8+y7fXsMY~P8xUV<((zwBIW{lNRqs#A*2Sr
DDL+OHq{N!Dz~gmV|KiOn<zJ<J2!^^quuzNEG`pr_=BS^9h*A-Vj;WZA)GAdmCC-TV-9P}xneb9#
a6d+2=nf;l59Dk|HC%j9Stl;jNMz@=X4AQ3Z<oieEf<lOlqDcn7)VC$Y}wronYUUUdr`shQtn(*>
~=A^)rfxJc2%XAmS3CXdo%+6n1z_VNPSUUyLr85bSi+_1x!1)OTN=P#MdO(;>1S_58J-ds8c1S?8
GsNjE)?lIgTFlG*3$9s}Sz?hqb%Uthd>@#N`+6Bo!OGIN8gywWPCbICa4`EY9Z(mH)dnp4TBfZZ>
nFa;h^dF}8MoQ$*&a8^fsz|d9UR^Z90uhw%GyGUGNeF4f{Q@-G&(|&_gg=cHx-R_?%G=bP80W4%g
NN-6o^&U8*Wm|CdRlLNB>%1tCtTQ+g%?ur5@v>*jKCnfRN9nCEMd_kvC4+sU#aOpJI?jAH^#&|9$
ZV6~un&}oZFwfPDZfAX;hS&13I1{M<mZdm0sLgG%wLXsJ^n?X|8?>D&GTPh+V9^xA7B3Z^TiwfRJ
U}|uGm}rhEBPM21EXYCb>YSVe*%V7kQN?r8wOlAN3n85gc*LSshS-7}oKJ5qhl8sjKuLl&P+jjuA
k_52N#|-Tz|>uix#{I2=8&sKa7lt1wVI66`sij_L1K{(h>g;5Za4M1QyP_mlkH7)3D6_#->zz{MA
@pFerwPu&cMo+Wu~s1#!(NBUZ%cMid9-ZJ_ravMEAbj*(0%x@eTp>WO~jZ_vp?hzI%yJK9dN471i
m-Of72URWlBWgtlkoeo@PaQ(Oi^xEmfI-=3dSuca@Hflm^jH-vJbC7es;d9_%Nx2bWZ`QLYmBTpb
TR|xU*dksJrsR6Ioq47Uc+i?y>PdUVvg%sPDH>3fHzKVPdZ&I;&72eMW*rB3RpUVAA?R!)^b=?dS
%MH9hX7*yL7dxj4S)(MQY@o+?C=w9iH8dD03V-81WbS|9H0%nnxDWFOhzM(;PVX-D#p5?gG0^Y3y
uTFd7`!4WV>A6^X_f=7<kxJRpz>$JK;(xKC^OE*uGuTVR<xDmwM)TL3xgkKJo80oLP<15IA#O`qT
NyC`Pc>JF@agX|~J;AkjNYJy&6)#&Y8(Wl<3-?X?BtwyRW!v&dtz=|xyb!&cY&9CaBUfunAX3OiD
a}6)My*)Mire=RnO~sZGRTXLS!ksA6^Eaq`qxDC=15o9^M|Je2LLzI*rcBoc6#30#OaSMXuI|GAO
sqd5a`6Ch1aPCR+v5hSpz7q4nRTxh=nqFiuk9CaVefqT>_vm*vncZIHD9^cup{3}@5a7Zm@}|^kM
Jc3_EWm{@==I6V6h6a+sXdBXtby-mUFhHl-x<73+1SuqOZ;rO!m{dxXzY72x-Ls?~TX0o$>a5SRC
xyy;cn{kK+FqI+@7%EqDThBVHg4T)h05XTRHKH?gVMO(f+c%jg}(JHwk`kpSClDfmT10ji+c-!Yy
M%Qe&?RO8EAPsz=9)^s;3_o^YzAZ+${ReR_S?Vf*>=(TP4{u4kcvzRlWb7GSlMnSYZg#jEgr~YZ}
--x;3{hF0^u<DtzG+Xn+k&>K4+I_BY-P`E~n<%``ZoaKO^rlu`n442r4sgJHNnf?m)DZ~6*nA8M)
eIF%)X#}g8A%I=%p5R6zK!WxBQ6$L6^Z%pKm8|u^YqCJ%y#mk!Q{4`E7`E|v)USb5zLUSs2$^Vez
|{)*ZJzII!GzNCv@oOvll-d*1ZPwn67#INrTxVGc9)jXIu?i!r&_Tkj4Oc=>qgQm$<Z<N$cFeHqO
!%YMosTMjKBgd~Lfbu2ZtLCw_2`4H5=UH8-o`t2u-&<(hfGaN*anh_8D3Z)6awe+z^ET6X#D6Y-Z
nk!7fv80`|JEls&TICK-=Y5YhAkJI&RVI!_`nUK^S^VRUUyL)^8im}m*lAXD|Y6;Ot&@&l#OsdEA
ovUhSHt=jHncG+j`s@>g^_ZZojug4o5}b@cO5j7S1Zv@scCgflf}M6gCOO*Go{C`zK4C`*h87>!0
IA2?fq=AloUU^aGi%_8lMjSNW$PeRG(sqC7H*i7U2)?Y-!-4utQw4fvaZgknpCf5+cBlbwK&r|S{
=DV`QqQf!h$3rL9qi!J3t(f*lEV)3RP6KPNS_wY!F&Ea_8^jCBfL#z{6EgX1xbMW(!dzrP;`67~~
mLBU#6P7Gc1%sg6FB?KOoNu#)`z;$AefHNjq9Y;qD+oq3b0ygn@7Cff5-Y-LcRfUb>-HP5DuqjPU
mxi?~lLvZfnl!|J;&MtU`c_0{TIMGC^GzaWV_I2cf;WP0%djcI=DHrn%MkwD(MV+c~nT`goS0Re<
M0xDhROyydVA$9ieswNRcI?Sce@378Pkk$tucwGs(Dx&hFNZ*P`N+qa)>lh)oDSEI3)ixEu}o3Qt
R62ZcDipmijLFS^r*Z^&|YJaO^AXpRyj!0bT1fkp!TWb{=6*Eui149Vf8(%1GEl%hM0}^1kNRjf8
uOi%bV(2Eqr}1@+~d7gLP{k$0aW>HZTD7q$b0|=+@d6GK4PM{4Anv{Y%rla^X+4!m5_RP`7TYXwu
l+Dt$SyRVm%x>;zq+$>tMB{fN5ZSxuIUWG;qI_zk*5hKh8VhtFGi-pcbQdHzJ|OXK_S>pb69BZLn
eD`JhwUW>p^X3QE1mtoP~$|gNYg-~a~rdR{1U8c29=>C9K8yMnT?vXyEDJBB?Y{a}KI&|y<jVt#K
(NbNv>mmqQQ_&}CO8gwK4^^vpDs+=g)0nv!`iN%*nXv@#7UOEL3Vy9o6NK%J49;KMf>t=?Ll^#?L
s)QKqeYsm%e_r<F>Lsy4MlKxi&Wcf&<N7dG84BP%QH;7${j@5AkksoaqZ39*H51QPyF^*gE1%{u}
LiYt5YBC`(-luKprpw&M((}dGYMY+voqfi2qlYC@d=8GgR)~tN1tlCLO7D7FbZ10OGuFfr~Kml6i
O>2J*WXot$;MHKIUUL2U1=r!4$U@N_$I0--#8^^RH3Tk%0GrK<tVrVY&V>_s3m5aJct<R(ZInv=e
P0#DCT1CvaEu~M6xAb9rbU0^Z*pnF!N`seGLRgHY<ZIv|2_1v-7dGqe2JyRMW5m3kS8coDcbiBEk
zwaSDfo?(FnfR!x+oQ_ii|p3%oV!e>Su!s>=NOBFB65U*_u=S-qI9Skeo6sRY8`PtM~0*MhtAEDf
O9bg$?P&iS%#4T2mDQ%=jsy%LpKplC{0JQNw#KNS6F#6TWCO&1umqQIm~?I+Y=Zh(~ByO*|fl1E7
0XTYF5w&p!6N#`6Hm33~M_`-4th&!U>%oySRz8amR9jKk#}PF)b6*J^k(Ji;FkLo|AD$><~?%j}s
~N>Rn@z5>Sv+Pc^Wx_Zf#WP3J{MnK8WKc;#UCj4y#<CIsrZp~qKQK8s;pnU}_H$S(O_$z=*`yCxz
-9}An`sjbxZpi;2q;tG^pr<^^Zp>#Hbul6{Lsy5NA5e{FyeCFfO4lNa5;YFer)T+TV9l<{xR%w;1
EYI(&9dkrFMxYglNfn6P)Db;qC~mYU5TjA4t8A{GZyiH3$IFVs5-?;|W42lGnD7PkZ_qjn>Dfqvf
{fWK(7FRwz><Vy;2r`NgK!Ac&YX7K2abn<j(^Z<SYXbUrbW7%<5OH+IJX`r-YGSdAR~1Px^A<Ybx
$v7C?I)aSQtcg0pe!Y^EkiV0nH62<BW+z%IqAJJ>xc<X<O!u?cVj@KyRZF08wE}HScy#J)}#KRnd
*fr{!+jaPe!qH6S2s>U53C$#XW(rb_AEU0_z(s!Ej|4-OR&hxEPBP)5Ne*36FH{#Ju8I1NZ0)5Lo
IVP0(JHT^$yB~4}l?mX)y2J^XUg+t=}Y@zx@%uf3Oq$RFe?iqugN1ZwEG<p1o!RIesd1W=NG>G1g
2CDhQ8t&NbVu%@LO?Ves95}{K*)d?8Krkv2NCv5TJ}!ol<O3rC(rL_`_-IWJU{K`BZam_dT~)$F(
UZgtN<($YKrCl+PL`>O+{XF1BLCVAM&UU(R~J-=Eu1QqP$6#Enks;9J<vkKs_D7u-4r>E%U<fyB3
%XCyzprp3{E|TJ}mPA-Tjacf~2~EPbDpS?wZ%Mm=iQUazB)tQs0FAj?1**k%*@eX|&(?D8urNsA@
R;V?-CTfVhtK&1ZJ3)HSwFywVP9K~Ze)B=p1B_pzh54RgSBxgy$c${cxO+#pcogOvfs<1|K5uf}*
OnU$-!_+W!2F*jh|BAjExG|6POPV#)qS?$zUYhY%*lHe!`p0A9jH5}8{S&pf)CLGE|3v;HS!~|KA
7!n8%ef3b_zofGrj5Aa2!rKLodg;aKtaRSV*GA^O7{BAl<ZaU!i<AN`)c`bjHk>2zUR@0oRuW(+M
VMB0<v|6`Wl?Z8F^%zoe&7l5z=reHQC2y?l<0pn#09=|mjrkBB&k$%hTeQ9mlThs)3))Eu@e6G$l
oehH?6y4gbuySj!*ok&7N*KW*oIs3ztV7?znxdSlwPO)8vC8SgcUza80vU3+rQdWBfeojlHhZE+Z
dCJmj(EC$`RLjCRwGOcP_F8at(q?*?2_hxonr$3bTq3%Yoyd{o7`Ci>PmJf)7vb^dzdumcvMND1V
m&&jtiG2ML29AB=A#e%k^6t$%N==3a@8BSw(Gf9t#&expJ5CazwHNtvEPrSW(SrCIYo_ppg3hQpf
uspZn8l7MR+lIg)d-dP#cPk(XB<p-N>={L^LsQ&kTnz=wq@tCc{gsf=w%;MXN{lk`FggZVBc$jSx
?Q=X$%IJLA1dr>pi@IX^5c<9NHnqiu@}-qf^#%QNU>`%Qx_eCsQHHINd#!GU8+qtN2@1B;3<{qob
WtMXGd;8j!?8QE-WbZ0gvE-K@8cEp;Iv8-LqaY>%WnVs6D_pFYYeD(w1gn4TUJy#9spnq<6Tq>vS
h}WhE;o$EDzwqpVOg6ZY%&K1QO{bK{*f6_Xe!L@LlR2}EdOr_^DZs3}tUK5^xsuG0<jpN3bV?rb#
)rAeUkgR*d!L&{!Rp;-d2-z%=db|J0ByV4riSF`Afucv;CaTc<<fEZK>-?cj9=!8ZXY8)2XJj6|*
-0E@*9J^`J6e~T=X4<XWWo>3rnS2C6p^WjQfs|)0vuu;y>b8ZIrn*6S<=mvw)t-sYNrb(oy~#mrB
kt%JZO30O@{ILFRXs{W*tPlw)$MwF4Rx&L^xaNt-qD2vhc@I$cicX!<Q7(@bG-_Q<st$G_@%CNce
Kj!P#apkZ&;{yQmsUMs-DmeD0)A;%BE4(%qW|;PeacwXeR6_np?Ku28+zEvbVg8iDiA~Rt2ly^`@
;3_X|C&V}LmjVbFOFHyDzf*xnWosjGAzq#2v#CfgreVCM4oNW$2_UXh_o4<3)`Fv~fd?IrOBHcYf
c1lsW(L&#E;!w*y6L$w(t+Y?!)>I~MxdJbc$b$;_4qjSz&7DJV)5ocnme1PY`h*@DQHT?3vO>}D)
U_$QRy1Vz8#^oZ$+Lbo7$$TLZJ;QcOP1;qvhk?`stcAM6?92mfY+Re*vSL13-L44e9SvYTlh(%Dg
OQvt+^q(->e%ivW4&28#L&8JkS=$6L-J4Gj<l(k57T0ONgBFR4uMO|vo0Eh43<m7VG0PBP}s3Cx4
CHBC=5B7By6%Wb+R6iAU{hMk=<`q9bHz=fMk6lePT9+Rc3)YRas?(m<>qxTRm1NCVj?Z6~UspZqV
p7Fg1r+t_nH~E7T4)ERXdVrVOd64Qhu{sgvwWqL0RgZlci%1=EBnr6IRvd2mU<t-*J;!u{<7sAvs
#coH@ravJJ4)NKg+%yq;xjJroNnw-*h%C;t0glEXsghTlzC^Rz(9D3G2?j8(gb+evb&J&oqI-vgJ
V_&`AV`Vy!Modo3am=>^F-g2}Z2T24F#u4_s>3>Wfb!tW{{dq%fnf
