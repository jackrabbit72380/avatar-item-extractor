@echo off
setlocal EnableExtensions
title Avatar Item Extractor v20

rem ===========================================================================
rem  Avatar Item Extractor v20  -  one click
rem
rem  Double-click this file. It unpacks the code it carries to
rem  %LOCALAPPDATA%\AvatarItemExtractor, finds every avatar item source it can
rem  reach, and extracts all of them into a folder called extracted next to
rem  this file.
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
echo   A source is a folder holding closet_index.tsv, or one holding the item
echo   .bin / .asset files. Put it in Downloads, Desktop or Documents - or in
echo   this file's own folder - and run this file again.
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


def rig(cache, bat_dir, out):
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
    target = os.path.join(bat_dir, "rigged")
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
    sys.argv = [target] + rest
    try:
        exec(code, {"__name__": "__main__", "__file__": target})
        result = 0
    except SystemExit as exc:
        result = exc.code if isinstance(exc.code, int) else 0
    out = "extracted"
    for index, word in enumerate(rest):
        if word == "--out" and index + 1 < len(rest):
            out = rest[index + 1]
    if result == 0:
        rig(cache, bat_dir, out)
    return result


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-rl~3wzr}k|_FDdX(!45R)`XJ*;6YpOtMT(XL;grDT$&co>L;MA#s}AwWrVCi~lOy}Hqj2T5nL`
<?UM>nIWl^s~CUx~jS!zwHHgK^`o}^Dvur7VEvi-dBHlvdWfEuA}5hnB1wwI-jM<{#A0dhyT3_C+
Rd)TuaU2bDXJkm8<kdozlb8EDQ7Z!Q@jXPbVr$@>IQh@$VgIAi11HnS!5u7OHuaWl?gg;wbr~Zqg
+^+<&F+qVRq|Ul!1Y%JOs>W-1IOGZkRV@LL5}$uH{i`wvepE<e0blQhYLC<&M9ewJpTdV_;f*KrE
fy=bcTee5$(lNpr4alZb~pWBmkzJP|aaC((c(M-+Kc#0zm)OD1%vG;JQ2rlYvn$PgnEL?`r-zuJ}
>rmaUr~!4g>UVnwD#~FVah%@M1g{d9)I7*lG+)HwJWO&ZdA$}OsngXmP~K!2<YD%Nq1omNSqoaq!
uSRTvPhQ**{kFsOrqfHOnnNMNf<wQ2<B2L^IPgZ%4Y;In3$T<0xbdXD*pTcOG=Pe@K07!xht;PG*
$JiX7!%KO9uLzAP!%oQ!Jfce^hh$+JO()^vg84iI#JiU2qEk&T<+`Hj5Suc!q5ctbxJo@HH)*y-*
973cd^ySP;|OItt@yrh2{or|K?T=FtRj;fd<^j}BD6jDqAgh6mnv;au0~_4oT&;^6SWr<uP`vnY?
!B!hLEhlHvCniuD9U#ScR7q(QAGExDqLGQTCH_`2C84ikB&%+>tC)rif>pcCN3gQ$>Jt%Lr0Py!Z
hdp_;ZmDhu#>(G5({$8z@Ch3Q^tg@gV7O@#0`??1p#J>&DghJ#v;wFE38Ef!*HM=MB8JN(SS}-|v
<R1Ngh2QJFG6TFf}tWbu!s9Fx}727Wa(9c;5D!c0ACkr#;8Z@@+pkNJWZ5GOTe8R`U((rx(x1B9?
ip!LM)hH$Fv)+5(5|6^*G)TkTq0E7{c<HHXp;sC`q6wAmuEAEejhD!E5b-s|0I*OItpWu@M<jc{&
XMfZ+pS{mn9+JDWv786u=|TH3!aqdX52br-~|Vy?2<SX`rs0alvCYuwGS&tk3+2RTCODv|w;)qeb
m-^~Kpgg0>tdlKOf&!PA_T*Ba?8lZSUP+=e>VT5q$XhMktglXecg5@otw|Vd}ON+N@W<F;5ay7||
uj|Ze1$HxjyEy;;?dj!@AI`=X=l^-8PE_}ychJ2`Uc7$y@;}BuoSnWp`=DR-`T!)r^ml(R3Lkg7U
2KQTzde0(b^*_SV-nFFsH?s61OOUMul8E}u!j#%VHg2I);#Xx<IC_NhmBz#?&Cw+*XGdyKDw9%i|
`$w<uU>qVBQ_lJ3$}w^oTk{y7MN?gDIfEj|o)Gp!cvC)>AC?as>y({AC)a%gX>ZhIxBjY2zoSh2I
edSIHy>`iA=)X>U07&K@S=0;lN@glNKhF8USFzJKi>o-4S<VK6WHei7vt^hi2n?0J3hq776Ph$+^
A*GSS+00QjeoaiK<qOv39<Nz9b0|z0Hnofa)*eE<#<8hQk`FQN%+0s%75<N-$hfh2B5U>INl-{H_
H+T*J29;i9(dTdsgUsL^5GIe>Ro|#%yYI;?oP3gwlhvHc+nq-@PA`v5A@#h}i&Y8#ErSS8e6xO6d
k8NC)N+*|QF}C1-edR$$Nr<Kf3>F`DbMPv7*4Cyk?-3Rz!lg$erv=>2U|yp?ZLS{)r23;Gpu~I=a
<0CkTZQ2Z{ajr#pMN=MK`5KX5Fkw7jNT`%IoHf7eKv%Y|`uJKo#8SKvBS@F=8TAmL4AAirb}fq}3
<D=Ox~;YTK1s)UfXsp9k3|DDL&tvu9M-he|!S3=w)g7eut7bpHIg+8^O>tC!LeFu48+Jy1`7<;Hy
Mjlkv>XGlIip^><+2q^8kHyV4(?;O;wgZ456BAUn;%V;-V9aC|Qer3Fa1v=h}Z>wWfM!DlE#>qHn
yoB+IUmZ>Fh(=-$qf)PTR8w)kzrEsqzgjV>sd%Tcpr}=9^A6C5kqO=+pzdJJ<w4I^AhrOTRPF2Np
b^+^pNU^u2IL%yKD-3c*Y`^+bBCBi1(NEBE2FvD05W0~IxFH^V1b|Az_F&E>SyQl%m$P154$6~pI
~|yB$KdizBc{wo3YtxEsk!Jah{G7;0tIMR>tq1CZ0?7pZWm6|9V<GhOYmoox@oOjA0Cvewh^q@lW
9dWX%in$~}*nO>F;T6(l*lonmodcCLdAnNE;$TOb@h1h;7t#IOwEqD3rw@Bkbz9!aqA@>#b1SZ4O
10x;@#yaa}Gg$FH{>KG&`FAolD{IF}m^{xd!?@|yZ0}?Wfw%os_V@J(Z)?Z%b^R88ZC(Q#MR0X2n
sD7tgTYlY8-h&DtXYO~p$n1DW@a>y#K=?bX@Ah+3Gy8VMT7IL75nqvfD3XgJFtEU~N;24g;dEf+A
U=R$XZ-^@L$riHpGaX~H}?+|iMyRn|9=yjwtF3Q0S&cb6NfDM{R2+K5M&q?0&BG<t%&lBcsvQ_q1
_$|*(50AaYKYL$ky|D2=W+egkT&2ab%C%-Okfq&;M4Xi!f=68YGUczs~IDrs*Vm^4+@+Z%!{SI`b
(2eII3Y;Dd<=#zSruvw(;Um>JeJKxV3S3RZKdh`>ofW!SyINo%+P*cZ!mx|(pybC5-YNgksLMOQB
&wO7V@-|({bMxfKiLa_DbR@QZ`tSha2-rUOPx>i0{T7ktXuw3ZDV|NRDqt<Tu&rbQzZu!qp{<Cv9
u7RreN+%&V^B6fkdneiLxP3l2eLlE-K0wt6r%#VM_0?aXhtKq}W&jU30N8tO#}Ad$)}z8Lh86$$?
AsFLPsmI*oE<Olj9}Jv5wB3ubQ3*<(>Cq30{5uzT@Q$s5}AeSo_rU;qE-$KhovU*!DXpM;Gy16q^
TORU&6AI974r-DjUmbROF&N2}umI;;`mJR0Y={-$8w1U3Vmz1l+pqLQVRm(UrHzo#9jn9*?;><W&
rus}mK#me@j5f%YT_%(wZ>^P73aVj&;fOJ}o;e+o;a_2H=Df&UPoNGJKBXDbUBLtkoTdavI`KCe9
^9R*Anb-k=nA1JR-v-7S2PLDsJob4Oc^eIj#h+;K~Q{)6$A(-XqA|sN{s(S=w90sUEg*_DBs~m8K
l$4|tA;loKN3ss;bQ97AWW=%Y2*0Ibih7GscgcF{Eah7X={SmGt+4Lc)8@~U*(&*jeAsZr53qwm?
k?*}SeQ0UZdFtF%u=0LNPxhr0UM)n!Tpa>RZ8ssIWhd$OiQ}+E1Ccxc$EP-$cw$g{w#DkZK+y9PZ
WC6TwqapSHGVNWH3tqELXr`I6^3C7+?XdEyaCw0$8bJ>Uj-t@olQaaGD1X9)2{X0sN+T9cZv=S;Q
5tAR<<<Tn1~;s#0EGRAo1<6`*YeLOZPl)k2-x=Z8*dCyLf%U@!{bj*3oO%2N9J&M7*S5e};G7(r*
$>1MbH<)Iyi$KszSmEnbirage**JGw4-u3F{CS1DY=Zx4;Dlh<IkfZJwsgV}}p$U_Gxn_Pxf1%aG
9iGV5;yO-)X(5jh&Oo2I<kTHMig+Z$!2v)AUR~||a{2v-t36i*gIfiQ`RbW+)$?1AxNL^1eQwl7U
mgneU21V;MrL>0KTv>#W~_gqu@XS-u~z%1yD#Nlqgv<cEXc+r)8pNZ9uT)LxF1J(9*1KT6M{sSIJ
8SdQ;TX{5Bq(KX1Z_o<xQo>{?Q00?2d*G>7IdxRq4dhSk|bBiTD&10B?Z1NK5<#z4us4Sk=Gq3)n
tIGkAuh`oeP`8CcTsqi4*mYuG%tpkaM3(;Kd|-)#U!U(3Ad6199Muvd6_uJ#CDoTZ`~s4l<N_>Ya
+W84jlT!jg46_89t^)XpG2<_hF2qb*Ach_``w~{AlN6^7@Zp?&-(4tHR1)4|+5dhYHLaM1D-`rBs
M5Rr8RchKVh)lJEl47~8JG=F|uKOsTl)Eq5tv$&s;1;j*G!J6A;Nix<vBqAM6Z)w4Um4KU%&0;Gr
54FtRAl>Q4WSUL88T)ETry-GUFP^_oM;u3u!($2kKM0@3hy9O(|67^=;Tj3%!rZHrx{)(qgIsel0
EzKh|iz%v$Hex^bqfWl3=;+9jW$nzIbjK)0o~-8}*1k{)DaFg{7klW(AAYMo}6TgYKdJDwn-ND7A
hIuh$c%tsdW3Jy*T1PsMxRahW+PIkOA}CezgZci$N@QM6H_5u%&M(R@?1LfSRda<%&h^=&}Ujm<F
7uJ)qj22cX47Q=(8JUv|~2@-=hZZo82cwE$d0<-QPu+l+>=b149-98k?#wg=+zUm(H#`5@2S=Qu5
d6$GriZf~s)c!t+Nt#@G4`GsKAjIU88KOLzSm538ItDfc<(x(I024C;64mVvRGi+cBVH6l3c9ZqJ
0lOE*jKN9zU;NgCICMk`Ykn!Zf8J2bREG0J_Ha;Q8GPI$L%O-_l{sb_rZeNW|;~|I;;Ey|L%eI_+
+4h)+(#skr)m<^iKQTmRjxiSxV=RGcru!&p`~EJzy&+y28eX+zHHK8O%d^BrG+4SHi+!!J9a^%?M
)=4B>o{uT>VOxnJt&m`<P?neAqdD9_*@c1MEK4m9l7uq$M0G9B(=gY1Q(mqv;MLBTQI0*qyL^amz
Rb7`sZCPB_^uct4#c;c`v(=_%NCVwR!L!WYrI6v!1M-Go`5nAcdu-y>rQ<AC7Zs4AnBLC1CX|yKC
uwP6ozPr_ayV_%91g;YS-hvgNKJdH1@oJCz!bf`5pc;XOsxgq<ljCa7bctmwm|pGC<nSqdpeMAP^
oTy;Gcsv_C;0dGVrP$+x7UY9hu)puz{oavcSIC>E>XNSZw`G2dyrGVbBbyn(Oc4Wqp$v{;3L%R1G
;**_^?k8Z}H&)KD;hUUUNx{{;(!uJblPL7VaIKgp=?gKjfWza=9$nRk7FvilDp~FJU@xlps;SZ_r
hqqJG4KcJ2{l)e0DwV@1+#3(Yb?@MYt;9JscrbKZzaQnH#a)~IJm77o7QAglB|S#)r3W}b&)c~1`
?W-s4a7uO<yKw%n>MlfOm;UR7jme2$g(|o-MPfEp6ZUbmI>?<|^zX6LgG)D5;&|}{p4q9q3X!l0e
b7_Q`lM|qP*dD@|&l<6FxCW?QqteskZS)wI@5vK&0IMm)!aTB>;Q|a$`x`8Neb0Yu=8d*xxDBxc6
{kTtA|T8OB|t1$nJ=^khYM2O1pfDi#5b7%P~&aWh}HSXFEkt1YgA$^gXA`Z5!=i;y?wCW-dA+&H#
fv*;1vSQ;V~5V-ANdYPyC73XGq!!(o9gXQAO*7D^a6w3gGw&ddz=&&>T>4n3Dd|8~N2LVzyLb*yT
4=>JN^wjY5p7X(NaiGo+M5?tfG*fx>B5J%^Vyqb`~N?sVvRPhmkKgi(OpN`xPJghNjW+))8-K;Nf
+O?QZ+J9Ko|)X`y0M~D6h3Jqa~{lmkWJ|`(k6$rB9LGP$kpkY87aBqR-YFwJ`roOtcJns8RSJod2
;rb&v)n5Svkj5UD)^O6Zs`T9|`}I|#=|dCNV6B5KShD~yF0fa9_)NM`+<fVkiwAL-lcm*g_{~C=p
rzn*k3ZM%5G3{!M7v2H+DW5YrW$%EVlKMFPq@yD9{eR-*e6{0RN%rsBLa5o@6f7lky`&Ftv29JV@
E|N{eNxf0B89rm&Rrn7EL_xYX(S#9<~%B0uSrDK=OEiqkpI`1hPbkNH2pNdWeC*B+#lQKC&bGqx!
0(8N-bxme{!48ir!`G^7u(g<AXwc8~tlhfmbx(8!P8z8S~UQNut``Fw3A3LM7ugPAp|o~iM&I6fR
`7H2?*?5N<0vH)$$wN&QGUyuM=>aL|GF}!xKMVWtj3tUZzJ_^`fM}45KK(GK-=N87~izP%4l`I4-
b+47iC~hDaiO)2W8TW*27k?ygm<;V6uo>Ih;eH9o6(zUq-GZ$B*U;EHyk4eoD#HiSekN!TzXFZ|J
7mKSke#^ob}*gl`!wR<rA=%yT9OeZIyx+(&=U5zwG=&Zu;<Av3_sOfYYF$JC0A5D@W-LyvPbyTDm
2ub^{C446@*<Ho&{Nu=gVTPuJ*<(=b~U=bl15JQI@yf0n|%~Tl8;=Ar@Jja%F@qtCC11&ND5Sj9S
h6qh`NIZ7ukWM4@r;1+5V0ZoyjQ7ivl$2RuvOD3zIuh8b9Bq!O$;AZ~Uz=oc3Tgh2z>mIcjo?@`~
uTzHo`CVYxtSLn~uB_9`3l-&EaT5T=$XN~pmO7&-^eu=O*4`oH&sz=!OE?wVIH&A|Ngj3$yuwe{v
hCqKF3cv)wKOb*GU@g!s(Y5ICumgSF79X$m$Fj<Zlz=st=a<?q<vPe=H)eyvVaL;EUB;7z^+79?L
fDJN)%?Mnj0*vGC3I=AGPf%oV}L6!Z#TWPpP;>zrUxu`sX|j+E~x#Jwv~f<)D<IO@U>m-xU>SUxy
0rH*~af1hqS3+?kpWk%bP0*^mZ?qp;sWZT|fp^x)yMrqexni%i`(r=KC6K;)(8sD~abOF)7xyjo_
tqb%PAe*b?=M;W%bTGrDw$rnSq%eAY6USC&w0Hf`fc4d@NaO-3@b#9Ioj?sjXXaZ5C#jC*g=fPmG
tZ*H)uY>jEPZ(B7MCNyc5uTXg!B;-A~hVy?JvdurMCGuIi%E&HBQynzrNgNYSTHuy8iy=!&?YS$Y
2*ygdplk<5d>>AuJYBjboY@>$7$`*Eq}jLJXh8sApp0-qvSv?PGSYz#0Yq`URv%Z%r;c;sRKkzv>
ge!rpSFdA64rBr1@LV9%~Zged9tmo>=GlMJS@UVPAVF2zYo0Z0p2v2j>xKuG=tyCKW7Ry*8SzgG`
8I?j<JgBJ({X%8ZvJ`r!hZb2S(3~jr^WAGb4|bXAP!hK-DsX@*QM*6Xax-2g@@_ms2>vPzjHkI9A
8gE)R2bLk30_@Wosv(6xC-T|!aYp6x4k(Kbg-L}teW!ZrPnaIQs<e*8(1^A_DJFh@*x86C$+8vEG
ihUtFjprhVf15-VX(PY&JqI<e3c+jGyxlGn3hczV8qHJYhZ-J0$BrMF`O*g&=Y>`GzRGmDJ_)ygE
9eFh(E-b3Jf^95DcS4)SBJ@ZcM~)8a+Rz}=^7L<4d!HgS^g_4H+&GQGmxvxN5KpW(1Dw%L9Q4&5&
kO7DCu|5Oflu)7@4M*~iYfK_$3&2C5Fgn8_e-aEN6sXhXNc_O7f+EYSrf$X<q0+&7M9;%Itk(}XC
kVXtztl+Y{I%Lk>bkpC?n$J5KqfTq3nC(*_Oizxocx7*T~w-T57*<Y@q4p!}4I%_jR?ktb*)LzrC
E$hvtGVJ5i<<tGn`(kLWg3ekiW|rKjBY76N21PlW=Z=p*nJ>*o^EFqG@xp;XBOtA9^sa|p)z*I%j
c5ORf)F6lJb^o(cLQExcH!jzqyQQvWRyszVnI1U`#;{HLub#Tx(EDS4ESk*<B<w*A9`(T}+XvWb1
X2=CCLrv<-P0C#~S7OeI)INAyO2?LAhi)(|1@?gYq1$D+2A(~LgG!6ba1lp*=S^`?K79W|d9Xe3v
bn#HYT)i6aP7x_N1d~mcgB$@FwQ|`%IRbhuh2mIiH<w~6le}i1`g?C7$n)(Y8os*p?b@3b{V=uGh
Y@ZNmv<TM$QBru_J|FX)KWxbW7<CtwtNzH67U_5FgUK+!z`%0PBf1+X$VX$;M$GO_nKYWpqr44B?
wdM3vw=m39+=bEl-6XSCN8R&YgdtW5O6%C4!|Bbu?PQ^x|wU}Pg;YNCWZj7otZ_(qf*IN0xRppDJ
z8bn?NQEwSS$#A&<79DsWsE~`!Zcgq;y`v|{r5>v6AFD9@Z0qja_U>n}KBPKigj%U?r`PLrx}E+3
f;XgnrEY>rVSuv4*g3|G-C+o}@&b2TOCZ>dWtMB_v_j((=gFO4UNxYKx;C~{dP{Uvzh5*^72Jb%F
cdnqO+*w5wu1Bkp-_SW6JRrXzIg9yhP@>>@yF!{y`%Dz{(*i{o}Y}P=)=2rI`IoFlDs;uzS_(qNW
EfI)i$m18C8|PUAVM(0c5?m^9yz{v;lNQv~Se@R<42N$_-2dcVYPi)t<+_Bex162M~vHZB0wcWWt
(=eZ{&RP@*^~c*2qyi&2mu?`FPKtX(wu#!|EiDkWg!FvnYcWjIq}fc2M3F~)u@!=EYz1b4}HN48V
Bh!AKjA|ES71o~J+K3YY7H^BQ!o!;ajn>xm52Z}DHt&)lhZRsMGBRw6zqcAHY(N(wR+S|26@9Q(!
G@d?RXNFA9!+E;Yo}Th>g96MMn0=a{wcl>+xLd~61&PHfkJcIC=6WtP+_GYNXpFkVo~wfV`}<`or
oo}ndZRt0@90M`oQ^V4bq0-YK3c^Y+Kw{vWY`@IjpQU3J?5L^l)~lzG$URLj227)XR|`Dj|z{mpt
471dy62Sxe9&?JVYD~TJqv8Dc2LdS(KOncg(l4Gr=^>Cd+8S@vA8Coulff)BQxHSqD4pOrs@s;OX
zdb%uYfAz4N|6O7<B4RUfwGF5Qnd)O>Wl;VBO8oCaJsM_-z&mO0VZ9^K5Zz4Db#=hU!Q7Nj4ZXtY
#vOM$5@XLG~g}y`Q@uCQJL6Ucvu%Gt{P|N(LeT)~0z-`^kYIwhCIswq)SUPAt?%m8vTYyK4H;m~-
?kD*XdEBKFzZ`Cc4I;_<cZhb$Xt_878pzf)VzQ2_5hlPgV;n$_8}xtICU1B+UaYe`oS!{JWZj&qD
)1B%6(v*+7yny@v5)d}GN!0w7~_vZNr`@+@fc@0CR8Dm+zpWp(IwmY7RPAAZvXw_-CMWE`(>1uuB
!fj{QbWNf0<65sNa6Cic<!2xq+I|Q0-v}_mOIQ`kCBs;03&XL<iR1sD2|+i~ke*f*KH$E`y0Jt$W
6)=p{s>2HY1E-%v(qJMW?=Gx84!0WC3QbVXRGdpI}A;v~^uMnlJ@t!AzqkMq$|_p4{uQE1viVO3E
Z@+jk2XNg!z<Nu88G%zEG**lty+HmEtl6KiL2x>tC5cIkZ8*gTvEDS$+72ji7MR?B)H@n_wm;+<9
S}c*n^cF3(T8uGjj!TE$Q!H4F*U3E5FYVRBnBY*fOb*kT%|v7mR{1PNebUcRvIXUX$uiAAH2BZ<6
nK%@z>fEc(L<>Pv6qo(pQ4<wLw>r^K9v_N=X5>PqALpuXUX^V7zR{(Gg2(jj(WjyKt<|rM;S(wln
^Eqa1<3a$Sa`rP>p#GbiQs;(2v5}T7ZSu0#|zvuCu4uETE|aRP*cWe6Fp76`(iQy5ExlSSv?Vew<
!^^cXRO0W*tuLW9yvi8kdnOD(}AdX}v*-C#vY4KGNQH3JF+L~g_%O$pEG%g~XpY)XP{o8g=Ghqj<
KD$%h5+7^16HVQN?1&4D-d8ZzAj&6!yyeD-dwv0+9rFv9GW-2LrEu-9Si|n?c9y;jvTWY_2w3LQ|
@elcj2O*Ixpn+jDYAO3GhMK58>W}OJ^GkNxtO2H9r5;Q;?sq-efL0K8!O*WTrYaLJnv@Ttk*5|e&
I5Q~gzW?hkFt)Az1lfl-mcJ9_C3AvEMEJhh-#gfz}6Vx$gnp|bBW3tWd!%o38vF=AWg$iIhZoeaT
)$&6)ojn0(~9g1$0ysWO-|g)H^mAOk}vcs3z8F-9PCsF#H=py>r_sf+K+tw+I6|Ac6h7#W*XlenI
SS9S_ER-ZL|zMPi8>VTRn;))rO^3XDdqM|cyg;+zRZOHF1eV$g{v->>%8{O9u~X3k8P70fKQJ#eh
?)dFxGuuaZ|hwby@umcXjNf;aFu#(oy<49s%8<*9uGo>p_AJA|{hP%`i{lU(%LTjWstujN7r6`b}
_5?w<C`M@5)wHZY5n$Kp6*bfXXcf)m(NuGNKs6XGVdE3kz#fVKr$HQ#>n(nW!9o56JGTY%IK?|3n
^`jBb(tmWx=#-axf5{$w0RVwB+#y-BbLzYCvHFpEakA<)VTzmsWPnEVYm_z!Z-`lkx*CN9=P@hde
q(rGTQDRW!&Nk%!b-L(bGCXBHM(lkCgFXwqh_7Pp+R|?Y%>j8btZJLEFC8zN3DW`!ZO>Yd%kliII
i{JsaWJ-*<ht$##Tl*6L@=thODt9hw(TQ&zir37RjXk|zi0n_BW?tw8M<9Jau=sw`rn7+BOS9*<(
{LFH(>aKNP+#fi)w40Y}-W)tZ{m%i5Q03~M1bRN$OXnMf(;v+r07Je~d?yDFDn1o|wumP&DrkKWG
poQKYK(#IK6pWjG*|KNQ;yP6xM^E8?ndU?bb#*z2BaByus4yNge>ooGxjY^lHj|I(t7NaW2lCkxN
bDGfGS7BNK5@nsw58k6*Xe`WKkDj3o7!RdAV7;U;Jj~Fq4s-i<7<V2JiArDq{#Y+cx0_FZMXS^K8
LdHyMDKGO-Ceb&KboYlSB*oeX4_U1N2w8I!TmsBzS$ziKorIM5w<GsgE4<UohW+ygmo`2BEa0bSQ
hI)G<KlDmlG)d47(i7ON$S6$7zU!kvJVu&n$u?W_$500p8s&F`0V1%ka8>&G$P$?^pu-31e<V2E_
{OaWF+U^+zyTY7^dAuPmb#xOzl11BhE>1v6h7~X{H5Q|EdGo$-rsE&e8kvaqK<Filbw;)%)0I^Ih
B8s|yy;d`5VxW<>*I`)Qq%p!+-`?x56aX%g>*sz)J^JzD?8EyH@4h>KefH=I{=G`?6AJJnQR(Z7g
xRM&6-nx#wv7q#1k%P~O_6s=_-Yy5g*9CsZ7Z(3hn2>AAp$7IX`yA{dFq5D92AZDf=-^@DGz}mn*
d};kUs}<=w2nyZdcLtc?Wh79K?7b|AbsC@E%mRhcDF=C0vBHE!3&PoGfuzJiJPRI7`v(|5GLr)xr
m~YKSPW0YM1O>at9=+sia1hB6C-C0_KW^N>*vO|HnJCcs1sxQSAVyr!m6Hc1JupdDbBV|J`LO?U(
{LWIe$7^LXeg4Y6hnogj7lTZf9AY&q(6a*d7aV2DRB1cw631G;7-0XgbjcZvOMH{m!SYB?8Q$^^+
G$^mj0ZSXVqb}@7a#3b*x|Wr(4EBqdD?HBqvMKhK!w>sm%EMVxDD(hVA6Q2USyYztVzk7dGHaRp!
mC6~J6m?@5iwbEbB?e*NTkVtCNIbgQvg<4(I2zmR$JXMRaa&5UuBiPBJ#okD2QgXbS1O<o7#HDd#
If*+la=`(Y_vW0QZ4xwvF`#nO_ZXvrbp@h5H0es&QKH__jtS2C~r#N}PWv!srtorF`BhPo$lJ?k}
ABrsnlWmz~ITEy{gFqJ!oZU>`n%o}NFU;XZkW8=kW9NK;9?R_Cw&iHs#(!ZFC`G2N&WJ)UMtIQ&c
tgBV543@DD~u*csPfs4|G3h0jZEgv7cV3M|p&=^%T#|2E$NfMvyatuBL93c`mowuCjD7pzli_fFF
A)>_Do<>V)wb-@p*{p6;3-r~q*w@KqjEuw3H7o?{lSy5gg!(EEcNfB8AmTOo-nC?#x72NzV!-3I-
5}FrTCN2w0h>52kO?7GL+Ldo$ca-_BjX!<<}~K4eQ}$>0y@kHId+PZyaI`<OVpT;V#cKwkWStS2!
FKiM++})m!-=b6vs6cLYGNWY-H*^Z=L<l@nbyZ5u(d!8!F~&5;tMPXFH|CnFZM_j;^<+$5|Ftve_
z+;&P^(^S7_gex|r*<s%aZaDI9AW_<SZ<=NYd^LKAC>kTlncovFwT=Xn}4Hy4${(cNN#hGzH=9z|
L&F4|s@p!SGpjj0%wp95x%K6hBaQ@oz*X;7Ds^)6%|M_tC@|Tyd&pI#8-*RylwA4>&jQ$(vl0b}d
?)-k0ygB`O{Oaue<qt5Zedihvw}Gcm<uUAs6SN90g_si9JGsAFhCvk%2i}axU7B4I$|m_ES9!&~n
fRpXJ1$$#z_Fmr*zGG6Q(Q|_cEM_!7}%ipYEZ8U8l=G^OTj_R2*&6%tqg2mB?@X>y`aoz{-)bLXA
D~L=|aAAV@ULHE!BVu!fA^d-cnEX<|S4<7ORh%c&x0&Z!9CW8jL7s%O#SZ44>B7%ImQ%(gh`Es1N
??UR=3p=SXuPx%BY7xDI6&7{2~dw#{Qj3&0Fs7^U&{tn{1|d#*GFGUa5_S2+}b(5?7(jbuQ|ZO3F
fQ1;;P;u1a48C$Xy<tbDziA%Ul(>No(cfky@KCn7QbNwe+sTdx*2p2?0-53wt%qzK`(rpt;d2;^Z
;o4E}C}Jc~8#v!NO_~Wj2j?!V%Ac|QXPAKR#M&(j*mWz^#$WCIR}r=iM~(EMfHCc3E1X}cUwrM?y
k{Da@&#xipY3fgE5g|hC5@1{y{r-c_P%sHrJCi@jkM9*r!eH$ZRs+)jZkvK;6#9y|D_n%z;DtiKV
1SdH(iN!dL}l?$X{iYZjze|kPE<YctMN|)tYbxnF29`XUr)4&qz5`*v#i>YM<Xnn$^z2Fe&Mmi6u
m74cFYhhs5Vq%8QTvit19AiZVb5E;A_Gk%MrVtU_03oUA?W2Rb74jtr;+Jkv7I5O5y9c#M5y;et)
&_*s<Dgtm8urHtWRF#(hMC`^hwtSB2ZOXe|0++xApGC5!t2T2jWs9xRTZIjahPE$iDg9S&!InucM
!`{fYK`66Fw*H?-QH&GCG8t(`lgjGCGYeM_^i>Qyd25p#hPsH1<p_}Ekp@ewd<w{pT)snbm`d-4J
pTe(P-+RX4`{-^&Jx7;XyFM$bVxm~zqu;z$!dwarv(IhnaN6$r)}1`58_X?L&BoN0h-EWbQF41YK
l}E_-@OgsN=8MC=ARg-LC@trrK!4Fu0|oTTfkvzHzeX5@Ntr4M9XLJwH)~ZLPCfGP504gBTTi!2r
_P4DKZXiYD4kgp2#T^tVc)e^5%fVGUDAt-6RsuLOu(w=^1lXnYn522QpkzyGt&emwr!wTH~3tk4s
DiO4(9-J8*rO!<)T-==6z-BNr%DmQk_<dg*{V{AiC7a)eW0SAI5nHo<}U`fOUi}ZHi|9Jk2y^5rp
H3sxT3ArWy<i^&<JR_SZ^^)2W1-q5x2V49)6P5XmaVIPC%<2f!S_Sa>{HHU_9dd`kG(I6`YYhix`
>hOHT*7n%zcP!67pmw#{HxXl?xR&ul98#<;~UC1Ok1k=q)%_y(F8BnEk_fZf|Y~`I^Q*sC!($cql
k@rVS86KqG&J=glEXMqty+1o&~5-Cc_HUt;b<0a$iiDLX+xCxf|z<o=`|r0c~=@#|VARE5Xf7DCi
}on|Y=V26YkK%5;}%0^+oAfl3I;*XMag!KnCC&wT2ePvrnu^@38d{yOR#_2>ADn8N^8b1XS@D2$*
Cs#g|xL~<fO6cU_vp0h0W5a&+zk)>V9{X19bLPw-#aU`SKe_T}eu*q>Wt#be69SLiE#|P7fedZj-
9A^L((jEHf0Y3h3Z`f`BEok4Iw!a(wcKo~FMtszRaE49+g0NoacA2ggUeBim;K<I{GDX?s;5&MDu
vg=7l6!n2)G!+oH6k_IPNHIkws*j(A)2V3$lA^{i=AkxDhjRw52Mm}G#YaNlnU3SAK<Y`f{WDVoQ
x$#Zm3tV)wr}R;|)%E9=WlRb@97NFTuq%?J0-#G<|#34N2UhuqW18BmH-Xr}HZ64S{A6#a;JM?O=
<;TkSM7*wHeKb$X5+Np;thO<ZI`&^Sst$TI5H8Mypmi{sU2?73dgT01<0DQ>uJVIWEz_g3z-3_>1
F89VT)iyF<~tOX^_z~4e{*naLh)I3_<#yrLS*QRqOm`J>#8#qr<ouaRh?=jQTEl?n}a*50?drby+
wbvuou;tnn>FT#(j&?J;{=c|8OrMXY#^Au>!L*50bz^9KrFNoR&Apz3fmPJ2jV1d>ggJLH&Dfctr
ZLm7{yetSu!7v+-+9gH;u&TvH_tl84@Ck<Y%31-5x>TJRx#j5H4$)CZ{J;xPk%bSJpDjwem-qkZD
+1;3x$L{Qf$+q(5M3#%p~VK>o`OkR`g{E5|ZgVd`%&uI8+`NYGL8MYERX_6NeZi`r305P1s>CSfl
@a3$=?mAE{QxGf8!ZIvdG0i5>!UVFv&7El@|jrW+t;6&>S}^aeHeL89|I$SvOuoqEhokwPdim-=#
xWGnY+NwiT+C1ySg@KsG;RjwJ<GPWRX(1i9%1RAfhD)yWkT967>_)oeB9p9k6i6>X&RaQse!Qp0`
2g|j&?l4}U#TB2!tDDFi^r_Y~oh3zjU2jjWjoj%D+|_3em-vvPBrb+%VKw5`$oz-;mMG{_E_m2ju
4E<7maj$FTSrM~BK2DeY`Tpj4_&fVwqI$FN_c0?;Q-Q38QWQzcz+q0UB<Fv8xZN+WL#GZZ?`=Th$
9}(4<0qQy7QY?YISEX6M0W#kY;Uu+${~)_?kNN20l%Er-}k(T{9fH^^F?>wJ@ynPN*HK9eVUDrdQ
<j(o$=+S`5@p2owWDdH~_X5SU$KaX~R5C|@F8<zei8)$1H}oV6rO!~scSTz+X~L%0UAA{Hj>e$65
FX_u9ccFS&2`>mw+NsFb`BrW9><3P2j;#+bkxq=d2;H`kM9V3cG_YYzPBk@fzt0ZTEwA6>j>bz~@
Z_vqtM2!sF#59Q1(K^*gF{TMw0A{4mj&i>8E-HxdjluYmiC75H0HD#r{st2xROqHFds5sLj8}@cP
UWPU6=!E%(6aWS2DEyBWlbt#0w?Scd$;OPQz=QyJk*zD>}Fl4ll5D~k*0SyaL!<q6WIS;L~iym7H
v<a(V2x0)94mXMC}8wYjesZs#izdn?1eR6N&K4tGcjKXl4_{nJ%}<pzIfQ`Td6{E}FK~$JO+f4H6
NfSq!d9!0rOqC}^&mG%wa1_#J!19T3;%nFNEaB7dK|@b50l8U|^NVqII|vFXH%ve4SeE?hp4rH!x
(1KDnzNRiSM>%)`oFU6=Pqn!>bR>=rLYsKag!hsKp6ru<c?HB>%aHIp6#rX9%`v9U@{9ZMd&^W0}
)GdQCu%pe<U}aakf2tSVU!mQqO)LgDZ(`^uH|%vN=D5qyp@e`mn6S5QS8pV)j=-qvRHI(kZ5Ip}j
VQr8r(lrlYncg+tx5nZ53kUx4x3o3RqQs05Xgd(I{h~t=8m3{s!n_K>Sw*t?|kNI#{q6&w2k<bts
~K`*Ymi|{ZU<$1Vb4IxjTqBT!?<g>7WAPuhglLL@cs^m!^?Ec9N8Z6khnYmS5;u7_lUg{PE>-VXy
UIJh%^R)++Nv?5nqBMbh!DYrtw*t?Jgw#;bC(i#8BB9K-OJg!MVvf5T=Fn_8MDQZ2rv`+^fs+p7L
4hhBBlZU*%>B;Vo4+}r^<$K<8Z-nOYo^TPhmAE4!(ZO+jkK{c4s&arY79UI(xXatZv-E;{(135kq
D2<Y5OMv+Em_5Jnc)@eT_q76}a(~So+4>FBE-6sxHTkK@IRC`^wRRgh>IJ8UG=8SR^7hWLvfJu#Y
UiT2T~D=7i|xbGQGXXMTC`-^(%yJns3!X;5KTyxK<AL_mQk2dn`XATvud{l#DnE6UM&4D+i7!41X
J;oOlhh?JRojEbPD2<V6;%E=UJhpE1Ljs85d^i+&C!HH!Yp+wATK5tGg@r1*?{GgJYi1Zhh|RO}p
9E)G`D&7T{#@y|s0ar0QLV&DfD014a+<Zwc?kY<w5rV#luBF(;RUlcOC(CG+xaLnga(93Ulji^za
NOX&t6HP-0c+SO+2+o4^xVBgj@nsV#_W<7Yeyd$mQ7lB5b587jmmJ~bJw%2p~(zbdcBPlE8Yi6fD
gXv_6E{~X6TZYYLKSQ~0v+SS5#vD_m6$R|5dIXNpHt#8gXtqn#TID$QK<v^;-_Uf%HHNg6W!jnXb
(&IS4pN@Eu7m^Ug4^yzkEwidZhSn&FScZ}RzSnCq0+5Yt=ptTLpRmrV)8<}-HFjYWik@C3Q;AC8y
&N>L1RM|=Q9LSvL?mxld20@V>|C9%&VxqjmL*7MmA?V#8tx9wynmt3WHi&4e|APUhQ0Xh=b~yyOF
5n;di8)(w8F)`9}cyJ?&~Mi{bOdnl^UOPboONPOOeQuY@|<YckogsE9jCd5?gPp`P_+RKuN{?>9_
ON3+RhI=%pT3efhzPnH!u;X8gWo2XE18xZas5=%sJQ)!22LJ5>0(D;fA(1qJL{bYyiu6I+mtC}G;
Hb8P1Hj<=c8bVV`did3rH0w#OZ?;(&2tK8NkkH#$sD<%vM{7>h`l7fI8vdM~8rOX5g*bJcFhCKQ*
B{4hCwRh!ko2}|-&b!!qQYXKWG_*nDpGP20%}>eY+2Fbk)cZvVrT7DW%cg*E4p|iX<F23z~pigY0
KLcT?R2Du~8SZ7bxqv-Si|C#f#=TfZgD@6nA~P+``&ME9|$*E$N<!8)fb9GMb=;ulRX!qU1y;EeR
+-G;#)+UZPIj3Wz;{Jix2C^+_Deucv`d2~Mfnwce7WpdE~SN!RW-*kf!qVBvUzbxSMjUN7G9&I2~
i-`!eE_A7e{B8>Rfn>LP*hM&djnntb2pSH=TNQh!vjXSB%`9wCx;}biB$mZed=8&iI3ag}A7?tb-
Y>l$3QDc%&wP+zlz$4cP!Pxw8WJ7<~fq$uP*~;B*>z6BYb>)AyN2n@{%MrIRvAy_N<9;D(UA|#qb
MF8^4l|mvb%Phs#wj;vwxx;HXYX8J%~x5jorCn%EjbjF0(o0%6J)G#YI0BKC{(JZiq`8vt+9pOvc
}5VFeSSoXY)Fj&I!U(tMkfAu=D#<O|o7Bq|*7zG)|Y7C`$}%H*B3ff=JgaO*1UfDz~T&X@L;m!}8
66X^s|guogF0jsn5q2I(oqP7dZegG0GFbO@z>P>qpClnsf!?2ExrngfM;#{e@f%ojm)n^>_a$|<5
#jE+R7>u;>zWvz2b30zT7|6U&3Y4!Y&yFeVQP6R|(A*|2EYd}(tX2H7Lm_8xxG+4K*FhipY_2xbD
%NOs3h?i!h^Ei+v>U_Z*<x```rnzc%azS}8Z_00~*^}kiI#It>F-&XeHL0pA!QndDt6A&jY6})e5
yk&54yL-od{*)0^R%fD1)P8)^+dC_iq=pK>TOhb0-c5#n42ntGW=jvU)tPYRWPi!yf_<9*x<;nXD
&JF`!N?qrjAfEzI$!)9asZA7^QT0d5oD*SIlkR(jC{9M)q_=#v%~NP!(1C{`Z<gwyIdS%+9k$;#n
^uI5yw#KFrHPi6uBVMo6~)tQvXZLvh)mbMUeg+`4TnF|-v%i_I@;tS+34QFwh(1YY97*2c_SH;#)
p_fR0tw+<W#;8DgC0-i%=*^r0Xh!|BUH)O_=i{Fz9vIttr9SAZftK?IX-Y2!=k8Vs$_Qh9IV(db^
sz--r{)>C@oA|pX5z*nd(fY3twRSQF++eFItfbYdzaa@X2RG=TltG5CR<%|MwF^nM#=g#P?!w>^Z
*4&&ia!B}v=G^DBO)0^zy@B&V)g3|DJ!7>eyw*UF*3y?b=d7vcIAyh`m|kcr_-^lak&kH5=C^d6W
10_E8>WN%4gTKi=}QdWGL$*Wohf>^pVqyC{zX-5`{5VGa(c0iW`>1Y_&pC(3E9!wAG6EK+(f7)Qx
9)Xh|uK>6qjvJp;jtBFzdr$wbp|>_!;!?6qjgEd5e_WuoF`d>)WlH)9${OQ8o8^hE5JZFHcR035r
7>a+@q=NGCXVbce7!TB(yX5kvG8G4UI9N1vEw)l~T$Qn8+BhAObbr{F2trljC6vsLPgi$X=I-P{j
QFC_tg};ez%o^!@;h2vX?V65F!$Ygl5eMW$Hq&pIHgK!Fbe_f8`vmR_^NN{vVdMSUsD$$c2dUHpL
SNDO!UDgh-Hq^%*j1HQa$vTxuI4vsN3@AjVtN=3dfic@nu|598arzakP<C21Hf#{-3`qG@gb!Mp)
xXU8vBbD+UQ8;Dldiop)6Kf;fP;sRpW^}kikx>?c%g`FW0+l3`4z=II+KL7)Oi%5@L7_j_1e$9pl
dr9LA9?!_a24u>Ocrkn=de2RmoQ(e)gyTR(v$2{osk2_-|z*!+&-F7uqR3`Y?|qwZ1&Wr{_c89Ug
HyiOtxog;47+ES)4+f*22@mT#w^g@yO44T$!rDLLceNG?5!Xf9j0o>0hd7zmOOxEwH%Na)+4z3bd
mV9=ziWP@0x{(XH>5A?Jiy1$82$Lwlx#9tEyNY3!Fg%i#p=}H@M+xKZf|#BGrO7cmW1OQg(te+Ye
GfD_y(hT5z$|}u2oKT9P*!+Jqf7=fy`%PZgb}s!JPzA%^kOQ)dyexqPc!HjvuQ>*K>R>rzmCLhfg
`)kMOlPqa0n~vqZoyW^Yq<^(>G`1i}U|H!%#*2r$@(E$(!@H<2R?5FEM&i|0;R=<D2ozA5JO4Qvd
LXAH4r?{^s<<FXPu|Z@<6%0bf1k7Z+zQ-@Se1zUm+R?J9w<m!~gYLuaSoon8I{kB<(nk{^Ej?mOu
0=NIRfSh5GrzyEM{`QhvgpI-d(=Eb|$)I_&<LCr{oBMi25{<iYG*QXv~0F}q5ug|}Kd-lqC{*+b*
L;PO;^8Rdm{`My*^@{cR#p9pOKD;=+Jb%N1@QdftB7>`V{Nvk~@7}<mFD~dE?brA3F3vB{-@P4Qy
naVLdzf1iQ={%5!2d_^|8Ywl!1qIVegxnDc8o5U@Sy)UbY?yK`SQc*ScZ*(hs;lpe){yYPd^9rb4
Wi&^z)Q{j`62_7W}P+KfSK}-;@9Q^8dd4e<1%K%Kt~=k*iH^#@DMTo{n__(=qA=Ok5k*)4*BV9jR
|{Ld9K)6)(TXb9KmNi0KU@B*d<dKfb7XF4Ogg8^}0}i{kr74dv<mlP9Y0c2py4=^DMKRyr}9-7un
*SM(8^8=>t~Pd$6aRa}~$1Md=gI#8a2A1_WXa7)&MlgmzGyjXqx`GL%gJ(Ibsuye{XyChJa%rPr|
bMc}rfo<6kffBlIqB{Wv<iv}5$`270v4*%^!hms<MEQ8^p;?n_&CHt9_@)yj3$k9om!(%QRd?m+D
U4_=N$6`|X5%=#$?Xd`97>VH4a=4C{+QmL@y)OqS6SY>rkg<hcBt!(%GVasTvf!<hVV|tb2@EcJ|
TK6P*^Io9g%~O^|$w_`W!A(?GC}0@|e1}eje@eJn(9#UmGXfAPt#7;pxXKB1$#CW=-5_X{N-6Hd%
y9!nzW;ue%zCwQ2RPdmCTNC5d-U`{>wL|AYoNA&6Ig^iM^G<yhU@r`>%7zg*<;eVuue|1~1nV?L*
fiH8a1pb>meu%JEn`x)BImD+g5<pwo4WP#DQds$$*o`yb<DaB`XB6qP=r6*+|J%291;pW|?oda!X
>b+)%79)C&d<Ao?m1TJ*VAv7x?Gr9uM!JpTlEu+;a?<4zZX;OBZ)G89(&cvoy}JtP&tOv7dM=}xH
I2k(dF(FNbG!)b@X=8WZPwudxOo7u^m8npz^BRuGG(ag71*xZDBV{QVxl!g-Gv&o@%(v{a+i9j*Y
4C383fH7juAKk;fR5Ec+xCa^~y&)eQ@~DPX%NCswj;Pp;NbJXtenOHZb)b(TOOpp8!G+$)y0?|8J
RzyQa~ob|^I5hLvo%gSXLh)`4jZq3)=Pqwv(h(%`=SG_(mqDO;{)9)93?4;s&T8h+Czj5(Yfv3(w
u1h%Lo5tO%|%Pe}#L<zZg%-taqS+2$}PPjn%9n(lnMcmyvU*vd0V4Sn`Jc$FVfQ<Pbv{M>$hKR9T
p#oDy7)&x=hnp*W+5ix@`HY2JQgAB}L1T))=lE!mT3u#ROv`#FGbyHJrQf1H^vgI*N-U~=LtiW=y
UcjedmUA$fWCEX!}7~(t1KqCwspvK;R_{`)!gCnc?yqVpVp)i!A)Tb)7<^~TYsJ`;XmfFmW~ErdY
>PM!3_!kX-(KR;ePaNYlnelo?B38A}5XmVBKwomE2c%=r>-WAyvVVlg|w9^}1p-wJK9;7Eh?WD_5
n&N;J;LaULmIPTDI6?X;{`$}^F(ZcPD|m;tbxBT@u!uhUp>XgU;1$cC}2_$6~0<=1wT#P2_22CfF
r%dad9rw!0M+=|%-ty{`bZu}pD=o(i~{#9fxb_}PquSe$_^uTm58iCcW9ut+>LhEuwZ#<y44^-Rw
t&LnxTc)vVDXS53L%)HzIBFb41le!_cLNmw3wEB?Zc{7vQDE<)Ek!AB;LgQ0jj<-%T*Zb+^L3-3k
KKMV_;Aw;qItbTKp#Xa64!bg;MYL-z7)eYFToB(c;oreOopZ33MsDeCh&B99gc~CsqiUvyiM6{fp
~1<a{Q_(DmwMWaJF?h5+R$`F<&tpSiH%o4t^E(`8t>?!$K4PQRbVS0qX-sbD^C4aXHwiZEA_4dyF
)uB`$$urk{Q__$(k4P<^Wke(m?R=}lH3%`N1Pgexm{qV{X#SC|TF-^y_$=)LqTS$*l4u?ACH7+ut
XLl2hAfLGjZq@jJlqohW6Mi(j@U)DV5q`@^W4D0Cty)3vGWzf>-eU^RYY*c#4cR6Fa5UC(9!<H=U
KoSxcwi?|al`!L~e~s>IxJ2a(fQr^KM^9b6rQ*fv))t_EzG2gl;rtsj{17YL`+%X1g>Ar0B8vNEZ
5&VrjDvcjg)*;tWztfW+mbR~Ak0eb6jwcuQ3Vg;)iDS(mHQRHcGbr<ja6@hh%qYP%#<4p;^;OZ2<
paQ9F=<;M?-}%hQ?a|Nmtq#B~!jD?f3^x^Ra}#ZIe@~SwS9jc0ytQCQk3O8sdcw4j=FoxT_HH2b{
Ma?!RHI+-QO+Uec*G1G+gJ>#<2H=>MtFqdrW}pshYTz2cooS=Dn#C+pK4)MD7GtP0sJxAZ+FQ1rY
U%<`dN7W-YlPCY8vPv;Lo+YnhDo~8bP)Ai~Py4r(Es#I24cdB;~sW;F;gv_$pbORFu?y*2p-XpF^
{y_ePnA^UjF@C^{2>?-Pq@OEOb`+0#o>c>_&*by=wC0pv*Fh05_F$`sx^7~c9(0ptUmBdQgyfCQ;
Es12+#wFG-~FE+-QRW_U9SOjpZkAk<s4;oEsf~=|1FTX^LMg1-8{CMp>651pdO-EBPK)$h(skZOd
at%6|Ee)zWn@BY(Lm!WT2y-A;ZnK7A<yo=U&i7f<l;!cfpj1Wyj{ne}4NyS=p({9i0p{#KuF%5+D
l|4t+*Z04O&4GIyQX%qSE^+hhY4bZHGRiW3un!epbRb9jUl#9gxwL1Ni^Vu>GY&N?$%03hgZ(j@&
J2KF^w7z-PH!6V4R@RNz)={Cp=AdeqWDtrhgdAw%GvFTMsZCPP@tD$6EUeRVLAKNQiub{Sq)bK5t
jSCe7l9G%*se8H09`pq#jjx@zd=1AZW9cng3>O6&Z{5rY9W9j0@|PL-ayhq%?Z7x4YYyG30Fj4AQ
5r2HpT{<njioAD-|!gkS{%3(_1#$%7n?kcXT^}}T^h?={h<B^r$SJx#Xh=&c5Zh5(tI&h*ZNU|?e
)hU%hrnqUPStgBfNzA*igxpZ_3J4BI6{TNt4AgRDf%5sK4k~llH^5v&)`Y4cA%K+r2inQXVVe+c;
0Bsjg+omXGa5+ZDmI?qbqv?|JQl>Umd$zzyqvQx*Gcxz91#LKu2gA@Z+PMQ&wf8D;c!TLXes1<(?
@?fd^NSbV&FJcc$i8Xq@c@di1((pVW?HY^DS2B}!rwN%v*Z__$#TWV=`i~bc4y-x)nb-YbqTNYtS
O!+k0eQoO~rf#cVblK_J8pRncRoCm?>g`ZSc+=txnHlyEkN!wasMb=pexa-k@i#7|frXK|b^}H&A
m$XCb}JM#2H9fXu={X!Jlb@`Y*Yvp(bjeXp6nb3e62oZ+fvwKXH{9;P@80)o$2H@TKHu!Fg@c=u?
+im1UOX_Lz~`KL@jqx$5PZ*sI^6`7;P9fD)Z`2g|d*=>-$@GR+kgpbkHhajKrXuVRvvqVLaJrbBD
d%t8eFEaQtQM^y}L>9`yRVG}ItdZrr^R{T6W2ik#zI$$)S&Mt#>w?cr3*NSHd$Exx1a-o0qQC|hI
3RPZnD6H}>y6)Yd1PK|A>&!2N>+NXE(Xbb+VDF1xp-Xw37kj-1SXh1Zj-At672A>s&$`<;-?B=k{
dQu2ZtHm9NjD4fB*`d;fYkO<i=6m~EXhMT#_M58YlUc#iIW7EE)p&Dkfxg|^NnQQHR@SC+Hqm+XM
;IF!h}<`0P|=XHqvxC|PEpGnDOm+Zk2hnfHEw@Ls6&g!tEPz&CiIFanX0oy&!5{jKy|>3)13}T9+
A1blLMu>4zmH$cyE`}ciC%IuK2q8QSZNTbp4%1*WWO@{+~U%jR%|SLShyXZKaR+(xCA38RDzamf@
kO=J<|qEfBT)O~%zt<}WlX97&->_}648w_&xvLvb^wIl9l3L?>>jt@eGo9reFtf=<JmHn|8(U(`6
EB#&+f0b#>Xc#2=tcfpSBwA;$p@7-OB<F=W9(LR}PB6j*5aE?=#Za%kFrC%!QafZTWz!#rdnTp<!
4UD7lH^CfGCtH+MWrd7A?i~(L0nzhHFWV2#x(4{$A2~o7O48bOxW+(Wd^NH4(EMnoE!Ep!05h4)$
1hsroo67r@@+H7mJ@a2sN>sBdM;<o&s4Mv(L)C9<MwjQPk-FPN7wMOh^Qkofg#Lhv|D|`@a?Rt4W
`{of82r5Er7p;@-S?o9bxmYz~u{IvO7GYEwI>uPhc?7=-SS9`~L*sHd*~za@B6sw@!L<Yi^bJH>e
T*6tx-OweEWO)J<r!>|Ro6>%yD#s2Uk)WRF!@o4w_h!-8G64rYz`|HqU+wl3#cBkB`FaH86qVTE_
RSnzqRj^<1BR&qq4t5_fr0~^n#CVddrt_hP>L4kJV@(q~LjrV<(;j&GHK1*%G21QX~vl`$xC~oV?
&vspHLvw#sy~B;|S)QtOb*sTu7uDO!QVEIxZ{SxyOjpTm1gFxquzNMDFU=|J21k;~>Vnl2xAMcmO
=gkjo5cWz{}`%`>LbgB2`b!g$d<Hb^G)mb<YcvEs{rS+w?asYyY8B)R?G8wG==%f$eLUop+TALwB
hjC6tWd#780Bv&W<<iP?_WAvuLw6F1XI{Ag)n>({DY80mgYd82Pp~yrnXdF72S`H4|yeD4(5}&Yl
^#Z}f*je<@w1ttX4d{POHMA|mM-^pnS`dFe_>sHa4yVcf}6nfJk$PLbB}puvO5EYM+-fr5kuu(rl
d25U~`x}D@!!Gmkg5#4y6Ehtr*5WE|TG0i|5)jU?DS}uAU4w6x&+E^x;)L6P|Yo5y6!tkg~?`rDW
rWeiB%OXS7oltkSoSbYC);4<_*v;CG2RpS|_Ec!F#j4S~R5=MMNryt7>YPz~RsU(%dP`?h*G6S*>
6CdUCRH(qlkP*W3;*0Sj%;>UHciY1$}8D5k|&9;7D0q*q$v^ilyhF&IoI({Tw1V3UY=``N+C1BJk
5hx;?fZXr+dg2bxQHrsJO4~=*UzMii^=8Cceb&ZOxW$M45y3C|FvH`|#~VHHA5uUqt;e^LG0#+2}
n!(ZlFCHla@KQqs|lE9bGBkmICMUcX~&`Ovo8(h>Ysd9KR9F$k)xfaM)zQmCs1CP<^OWA~|985z8
WwByXw0BF~{$u^F(j7@DbNh!&1ITqY9x*c;IPAekZhv>FQz2)ZGNp(u@AA&elFV9r=DU8EB<pd7j
y;s3<&OzWltddOUI(z{=Q)aJUf4!EE?KWDS-g2Jdc6+hTXV8c}9C(TW`hNY@?{G*t42lB<tXOe4k
QAd4>Cs3+wQLqGB)D4dZ|!Rgf)71Mi*E1NU#}AQAdDIo*ng@E5N7@QE1TrE7vU0v6w-Xud&(frIT
tA_oP^|=UnP{df-+0~`l|sNw!--`<^gikYb6Qf+8p=}b4Gtlxk|(3t;B1`d0!<(KGz$xqm776QA!
IOHD&ck=rINo#T|lKerA;YB3*vs2yhg=m?GVE2;BHob#AU7=q<wPYc`1Pe4Jx=_=lXsWYW6nlth&
GD#$Q@rTWJT<a~^zr`|*yF?|8tE?ODSLyi)N87MJxotcR&1#G`G%p_6Q9VTey^c)%5JWtmgxs>Aq
QgCKk)!<W@aI;SG_pdWpJE)`smttTA$p?aHA0`q2kBB=kH+X|ag`!+GA5HMbEV$Jtjlst2W*ls{x
xZpZwA+Y=DB5M1+H5k5FqN-t1O~Zn6+LXXfy21kgI|PAQecEHa0Q{U+i*%>le7)Xq(8#y@JBqQG2
h$Bj^7u}DSRPCm(^cD*qoU!7|=jIX6wwVa=lnzB?MnAk5P;>C9i&>G-aHY@ls<Qg-u)maF!f)k#^
fE!5~H;Ty*&(r)x&s4VBmJboaXl$7)V?@E8OAD~!t@s9xuIUtt!i+Z7qo)9N4TCSajsj*v@foiTV
fEC{;2bYba!IDP$Y{Nvm6%Zu^*vk&7p=;Vf%XkF+{JyH7|=#fYMck;%$Cei@pKV33{ws0eAT11;3
A=^<uVxUQ#nC%9}KnC%+)1cQ^XWza1@Miqt-P<#YyQfceA}4AQ#&=Q1QMLI=wuq9j@}OrwNkY^C6
yIl*O0ng(9IHtj+(nbvX)IQ&1yClyBljtcKCC>%y;W&<S=;Wiw%ui2yUY4^V<eBaGj{}&07yV-pp
=8JJf=$BWu@-2sB4|<lpIf=!I&hET(PqbejMr#9m<PF$@ws>@?+H-jPPXV2jtf*C0R1k$)il>r{A
nl&`w@GO7#-mny~t`&FycLmvX?RZo_F!iUX)|{eWdqT*4|JxgY&iXL`UECGa#&r{J$e-%AfUq8()
mv;&cGt_cDPm2*Q%-Aia<f{;wKMbM$S@kg8&f0A6Al&+BmS5_f1+=kffus;}$oUSSUKuIv*=M+TK
QK|B{Pn2YaWI)ySB~TnyU2mNZdYe07&^L5IFTbdRiV#{ZrXBsMivp?PxWoKDcu<*$juJL_2rDwuv
5<9{q9%o<9cPm;DMD`ox$mTltaCr-%WljMkS^EggO$Tso_VWGtU`<YYO=W~?)w;z3JIpqnW;#>oj
I9x`CK}s3Y^0hBYKAuiZB=$z6}*7%+G+7zr+)o##$%eP^K(QR=PdelYmigTRK5-*2qP7;^-RaS`=
m-lo(_lag=;I;RGG%$7PcDNwD*Q9U=ywba*n9S&ok58%d*DgpSumWDvo0>Lkm=3S5E}5M+mJH|@I
nIz?+U%vV)Z(T%e{#0**Obm&$h;l!AB!L1D=EGa?CL*C)_lFW6;6Uy*A2vX1L&XTDK7CMVSwTR9k
jin0YBi3UKhfk2BnpnEgOH%{RZE)=9TN%L94{uH{fBbM(+3YeDtCllFoeliY$y#lg<xJ1n@Vd-_7
D-XuZFWZcOHL=wj}#>?vrM{!B7Z_vi$L3}IR{H)0)ySsuOS5^1%%rQ4oYZOF}2P6*v+c;C7BZJ>=
BeTf%ZQaGm3~+Qr@IRr2b;;9Qogzj6)~l2`|8jn<YS!uTW~E->lSDm=B>;w4C8aAj~2e7onxjq&W
hACA&^_*HU=7<`sq};5=Bw!6bwpp5VNoXcjI?5%o(ejjdLrSz-EGo#BNi*P{M)TZ|8n(18`B?H5b
KvehiO3zZgqZP`i3<HrtsPFJvLRZPl0!6d3zkQ5ejD6fx=u-7Oegp%~roEw_pa2ZOKhKYX=&=~%a
GA<|5B#5=?cm~57W8nA@<f?@vVME11Cc-f0Cey81iQiBX4<17DLS7p`+khJoUK5u6ewpT^@|brj=
Q<|O;E{NE%Hrfsc+V8+ihe;D!9?$a<<xqncfyhr&<<^)T0>;Z;3=O~a=b7|M@4R1PRhEaaUMh?)q
Zn!@dI#RHb(KJfeJp#Bo(iNJG-PPV^)^82cameZl0NJ7Pv?}V|*S_24S7e0>{jglN4q^@bG())kp
A<3l)fnosIdS$A37<r=@iy5<su2j82hGPBLETK|FVibv1%8G+}Gwkv#_a)-xH<U!7f?y*_(+SxKN
>TA9j7gqE3AlE!fdm9Bkk=HV_1@5hvv(69|Slsnvf+{LgvYMcNqk=1g6S3C7#uo1YfX|+Rs-bvW2
ngkpBInA>2(yT9*Dc0Aa1~$i|In41a1c5g%anH7<6*Xa)#Eexc86SpDKC^ENy&$rPpRq9MQB3TDb
86`ZDN_40x3C6^U{}PKnQA}q+t2W}qb|~db|EQ)*10|Jp{3Rs+CjCSEAKM}Zdh}&Uf_a3U`H3j)Y
1>}jdz}=n7NnLD{-3YG?X?wV&f8Ue9P!z46<1~<#fxnuR7<L>?q3DCh&_S(Y7lTEZjVhM9o7FcXI
du7}J3{6ki_fFKgcB{6KF3Ljy+cJ`GA~iWn_4p}J?IQoKqem=61#3zGqiO$SzDBE}4|uYA~C9>cy
<<C5$J7XVdM4vML7RGs3?S5K$|F4R)Ju&wPd=FxQgK-S4PV2r^_o!cEh=E2py!-o5vZqd}bXsWlN
sos{Rip6LZfcP9OJZD{6x~{btW=(M*0?{to$J0c801!d0rQ}^tzgrjY8g9mm_0daVs#qx5SuHRjo
#*mGm|#24dB;5J^lt2JLyAz37xYnQ|E6-TSs2dAp?6vHmW<5*^F)|7sY%%=PQ*4io8TC@MF*D5)8
bqCHk5R-Mg>dc1ht?zk0|zWX?0CSG}IAYbnB>?`@O&pYR;<3B%8Fru1tuJI$C(Q^}CgzQ{2zcR2W
e%0{k{3U)>boNf`h=zs1es_?_pj*rb~rP-0~@jczCp1TuWs{?uF}3^47GC{nJS?6JE~_0OJz3B|%
q7RMd!0=?)UU7%in67uHYtedj1T2C9N>}!a*JKL=P=B>g0RoOpKV~B-1=E({U#Hr2nNWo`Fy8c$>
k+^qh-S61;p{xKC3ft{;TSS_B_@Pv5n&uvj14)tTvjh)Qhfo*@8c**V>BlcR*YLtU<8lRhAyI6<i
C35zBs=Msc8$PQ-P0z=Yq;Pxh>|RKE(lWvY)u@C`UgZZ%_rdnp<xYPAO^vBbE`E>SC;968n5}{u#
NY(Q{5uwo^tPlVNrxOW+~r~0@`LuqX5!2ii9*Rc07h#Vobs7;T&VZ;Qie+n&ei->qKr7m+5`R*Lt
_W!evDoa~^gkTV%OPYM2U(P&AMw>5Sqwov0Xw?dd}D4zH*eL~0TWCS{XeK3T?Gq?3gA9+o*FPTtW
FQU@l<?l#7zeBc$zt%9d9C!U=vDdp7a-2T562cH#wX+oEHAnKCX<hjH`PRCt#vdAl?b5YN^RUzjZ
svTBr`Q^OGpThM?9L%q$0olF`=r<hG{%}z2h>@K}=bXfFz)&I$bZ?j5U^ap<z_?pXBc~~B?EuHF@
g-Z$=ZNfpnLR6;j(&~oA<v*kw~9z2G#H3WI)D=%a}Us5i#J9WOaQh9YMb0}C)(&nzM(RfJ0~Hs*X
g>no<~zDT%z-ggQS}tQCj+;tUh1&m<FEkfKcT9aQ6Q7>B}?Apw~vSMX+SAZM|0-`E)Khj(9z+8ZN
g^?-A!TXOzO}7m<CD)2KYQ_7g}(dJG_|qdwroR^gV~6REE<a%Q`TU15Cz@?BHDCFabJRjvwUYuda
1pUN}=+a#7}av+2cq?q~$JEP%Pu=Q0;;>6}f6i9^?2O`ZJFS|JrHr;EdY1|1PTrNrzy@E5?##)T@
u}9*}Z>HXW*#=o{VjQ+LC2U(vxx`=$S9{-n_0?DEhqKdHXCD-NWUb6`zuV<c^!lf>4;Sa}-WKnlS
})(edv$ifuPkjYp?}K^B}`Tzt0OaBGbktToJM~FlUyLvH2F=3iM-|}r8wOlx2-$C83*_(v0D~(Kn
CKZ3O_Wh1-h1p%Opx2r3Zmb>sm>S03?3YIl9^Wi!r<uwo5Odr3V&u*ci4|OMt+1AEjgZyOzJ7OB5
WZf`#bsTK;~PzxPHFOe_AlSaR6KXCKZ_U%N{;$Eim_JT_R0PR$+tSh#ogoi<My{N!>$-yco+rUBQ
k$+X$R5%R-!aHK@+ctlt%^G8Ulhecn7UeaBkZ?$UColzq=0L3rQUs{O#B`gCS0tRHi(N{*@0lzD@
IejfN77jo2yH-{I`<n~8E@b8_0U9GTha@xD{7XDfd4!_xCIcFC)oZqzwqE$MgCaqC784S10oWV+5
Br{9usB>~SC(n?uQFJA2LGnK3a@2tRT-5jZx381<(|^zsxq(Wv*TjLC%MhVc^<Fsy(n`mJQ(sD`a
Rn066>Iaj7zv**lAWf_}=QmZ*6LJ8PeR@v|u>sk17{kdOjtN#+v4kg)^QI@PwmsBuYG|b$QGQ({E
_Y+)<I#r=LQT!`{fg_L9cBd~kGu6v~qxKk50%W*611wt6+ZpR@*|p|nzA^h#8tyN#kx9jaeP+zD4
ZT3Ln!nLm7PY2<n^pVsD6nW&dfzpgp*x<;;%lx$mS_Ds#*mYNz`hE>%-lLz)fk)FRs<=a`^@g0Cx
{<}%S@l6RuRul%Et_{d#!`Yb7oLjnl3cD+@x<lZi0MUkaJ8OHyHC938#qV_KpVA*J4!v?-T*BG;_
WRd0oX;YS*SCD-UV)Ch%bXkgbYWy*dEdc@z}Qde+N+XhovPq=+uwc{4FdwnC<&KNA~36!b~UzUby
G0fPpj-YTl!#2L;l?zjr4KG$NO#$?3H`1O2a&h|K8TgM9%HOVHhm-0&(E%?JHh=zsYXmzGOEMWRo
bOXXvPaH^IUIHrZ0}gAQ4iWAb`5L}tE*283#SdFm*+`Occ|X60VBg)0b$JzmxBdPBSAA4O<xI=%m
dru1epG9XH9=$&gU>{3d;oUxf>=9MgE_~lRxMMrg3GHg+f8m<IMF<amR_jE({|8@RJeItt%_I~mx
x*ZqRYPJbqc_hBJniWm^N!jMgYRa9HE>W2aEcGmnr)X_oh~K!-4SiQ<#O?6q<fA3yvMZ(=uCb8O>
x8)?AUImxH-ZAqT1Um~uxw>k6^{_MRU2qqCfkI7>;(*)t*r#GQZXRbot{+8y^2wZQOn2$J3XzzAA
>Ih+bU@Hje;lZVBX3p%*X1C?0JEQAq$^z`l&DjWdY#Q^}-<DAB}t3#v23gpN(TjsIAj-BpbIG#%C
GmwgQFG@c}Zd=R<p->ojHe0c`+;m&5^Sr0>}ag?vR+HcMB)YhP<Qf*zh&#t?<|7VAq8@D-2+*JP~
aIVM<<m~yjqI7z|q*D1o5&Qi$l;BDX1bI(LTTNn}>lv6+DY~nm%&mLomCAYG@61Oy6SC-p2&s1#w
3_g1J8je6`=%ihg7ek)%s6a_JPp>tFYX+t<z$hD5RpDI&OBxVA*W<CknT-WpJXQ7~!nLN$0Bxj~=
^5FYVX>oNQ!FS#W)yUTkCqg4MG_=y-ZWXBE*AI!hMC?2&vtOA=EmTG+nbBi6W+|Sml9ev5H<oypl
=v`FmrvI)C&Dfk`PZf+nhL##T+1b@GMJ&b&XX~NkpwNMQS|V;EW1Zaee|kq+h!HgrU)pk)Q~a$r(
;Y_Kbi~X2mphM|e>}`bV8UoPsSfeIe@O%$-u;pz$6qe@nMr4svVoM?O5Z5s4PIH*)NK#B!(3e5xR
4j9sLlq3&x;E2*KaOsi|f!<Aa(!el43z`H#Cu5_<dY^;iLB-beRpWF$^6r)7y4a&2(4XxOIUAI7P
W#c-t-YTUB4v_Z9SVku<X@149FbnR&agdFX-9gL3!o0BP&f)m5!c@~Cr%aWsY?y3@`=FRcwumFta
97#I8cW(LS@C^`LZE@60SS9`lyJe)$CsD3nV;MW^G8{SdIQMd{K|H=1xrGnEak)F4;u5;qfSj|2E
#*bF1D*VpL_XIo`nFIoe5yRUVW4i!n9rBN+8p4tyv;;ap8F(sMxg%wq(2>lS#~2ngt+!_u}XA#mm
#z7~=AEjk}f+;MfP|H~S{4WsFpR_v`4V7Khy7I>rQD7BM1BZ;1##9<%N1n6}_}Y&;gwV+|O#++#@
u-MN4Ne*pq?52g
