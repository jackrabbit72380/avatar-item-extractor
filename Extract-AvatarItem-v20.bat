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
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%" --root "%~dp0."
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
    sys.argv = [target] + rest
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
c-rl~3wPT_vLO6dF!JXK7?Ctd$+E&&-YeU3qC0*aOUWcdaT$n&B*Y}ZAwWrVCi~mBUi}0>(urrz?
)lbHBogRnb#--Bbv=IDiEg7JT8w6Ke$$?>cKSOH{_<#<FCJYc>7zKk4d$!jCQJ7&(u*DZ?`1sBCU
L;Ef*E|C=0UbBg6t|driaIQ9vAPU@yB+Nje{gDvf$nG|87GA>G@5P2k=we#KA1d^CZ0vrb+rSxXK
pvaPMVso5Xj0`Z9+$g1pEUaUR6c_$G+3W%wOL7wONz`F9^4ot=Mp9*ncJh>|p31a~)C9tUr5P{HL
igX&>23HBP;XB3QYpcIbt^*?@UjkDPt8qVX%MM_2U;3k_+a70mXnG`MTJ)Q&vm*8zy+~BL5co9Q?
%jqPzjDzbXH4t1Zd!6onkQ6YF=`_2e30|ZysaaG6$!tE2XK`9U$;*`hDL7s(q97bEq9V>8F*I9TA
#XxUc|5&>fy}c7LiQrPkJBXjDi1!!i!`1-x{qd3DQ`4`yQH`wh{42y2`$h903S?0-NTX+<OBF8D;
c;e9<*qx!PAP>dj>BV=x?HF{5+dr>Fn~?U<O~?@By2Ck)>D3Vg|E|t^vS#K|{%JlKC8-VcUIcU@$
v;O$%o))EuUQFQXI|MEABz;^`z0y4}4e!EL-Kk}=@IqoCJ2*bj<D5~bHuco4pdXR1cGx7WiG`;Ye
<H1qdao)k%z=CE$Fm{1i!^ZfMf%OHor#myki7^wi)pm$v6tK@pQi2G*NvpCA(Nq&)b+fTj;qG<-D
?t^eS2k>{>kGt|{)eJgq7%PAKMAHc_qmS4qpvQG`3&YLQ7_cWT0QF~=7b&0spcOzRN)h#-yLNC6A
Y!<Tqs1bDO7nQpLI}k7@FIp*6BsH&1ADlOlj|EqoIJZo5xg2!5#Z}Q%Ng}(T|UOsxX98Vq$S`^9y
bC&)X5^c3yNeGw*$n2+2xdW!$qp$BD)^P8w0Y&K^n)fJi5(Y_?V<A6a}QbNnp#u#zXL0d*C9)+TY
Tak7R5_MuH-nL;%3}p0NIEk<FaVBA|>BQUxvT-xo<y#A$FFO_ye_vf5Z&p@;@nmQGi=n_-_#xxzF
m5K<SZ?02m8!;k##CW1|PHO*j8BK+Yw6ko*)7(7%16psih41_dJ5H4*+C~<%=ZJbK9xF+=04}Q%v
^ES)%$Gli9$A$U2%B@ylH{-Xn)9>CMpa1aTWOR1=kCWgi=-hYrI~VEm*Y95ZZS?)g@ynAB>Q%P~K
mtsE_jgnHu+!;aJ6!(l@tcz~c>Wuch)zGa*f~uBpvmN7r^yey`0yBp5g}yt;~qXfkM9fE82aHJKB
RrEAMN9#vzurhzXP;fBtQf7yT|lS&__Q#pbnAlyorlw0x0l93RQFHJvPI7f~8(8;eeRE$fnuiJc5
m(-yW9Q_|a+McZ9)3I-UZ3!+nmlH=cwi_v3hu(`@vGXu^9g`T%I(pZkaB3a)V+%}n3Vlj4jXNr#L
*ug{*hfT{v9#X9gBNqPoAfPGvLo#azgcBGsfKx41qAOup=Hb{t#!t-D>O46hljY2$IngN1DO%ng%
(>6W?Y`{O>o9yZe&jG+7??s+`ibpWW9Nqz83aQ=T>)_Dtdwdg*KT5~xaz^Ft&XX&rmt9>bc;@wDR
l<LZD8Un7uiwQE!V3YlSf)tS9!`RA7k<I9|8UZ{*a;p6q1BZcPSfkC(Xc0gE3kh2)`$=GH;xk9gL
8YL2tS->Sovb7;enSSr~5Q-;WS!K{RO#6uDnNj-K<HQx6_!)tLDuMpx!_>>Gd<93hs2EDB#ivF%c
?D4-aw0?NSBO>LcLu((o{7*_E2qaKkM=i}H_9JnRNfpHkfhRO-5Ah|sIKAfgSV^JmY3y&?X#dhwQ
k!SyfbfqMEYH`c)32yAX~hUD%Mjl_LLKxtLIQP}Ihb5Oeq+KU*7Xewj$(QdRnq~Z$we7u7NI^2kF
%frA&xx+HX$v9}dgz;&kJeuwSjl>>Csb2S>qT*g}bH%-0xnfdL@m67hspYkK3+Thh1aA>gx3K2&p
xX#QYymc@+}FW=EwJ4_(}uSU$T^rk!W7ZB(ePI07BPnkq~#HpMsu|WWW*}8m&CWg0zbWiV@*9(&r
a!?4W>q8&>7nOM3dVn9miGkwdqfz9-E!krpa|WDzZ@ud;#sk()iueBy`FClLi3re?6%jL#Oe@&fz
=;#&8OhevzAl_{Vq*vgVn7<(|jPCbs^$jM4($POvyIJC{+8OeaXWO%M+6qw6e<rmzh0yh$v3bPpU
b9!aqAikp1%vCQm231HOkXaNl85)WD~)z(PjFAolDbiZxE)wTscZBq~?0}?Wf*6&}@v4i?5tIx0U
Y1=BmlNJ#Vssz!mgI>E+S$<VhK7<M&XYRE-$n1m%@a^lbLHK)I-R-BkX7=ogmHb8-BOZ`^D3VJ+U
|@k|ndY$n;z?i2L3{wi&iW^GhG+?YK9a(~ZtkBb5_j6|-v1;tZFSqh88p;_O&qi2_fI$xV~}Bj7+
9+nX+?rii^t<=7TfKikWGRz9ydf7qkJ`+#UPKNMhM0c5l6P$>a?G9yNz#yY#ygAQG-mA%dc{~xk)
z8AH90_;mz^+S$j4Cpzooq4ty~2z<9_lrz{{M1Ez;{36Pm6or2XIDk5-FP#JbFaMB8H0QUJJn=Hr
N@(g6rXk1KDg`%o^NFDk(-_X3Qy%FfNu@G#vzLix~E2~l~pVqhXsj8JvrB-0E43-N$*mbwS*TKpy
|H&!;$u0j0%71bW#}!cZu6Gi0GrP#~**nQ@$L;gp>GR(0^B$_+JAH=KX(RXx^zey3Rt(@C2LOA|?
fAZQ+J;oP$*|%-pBlCV`6DuuHD||jJR_KOollpjXu3-7<4KG5n!!Eld)ot|8Hmh6b&p;}u&AX&!(
pjOd~jK65qPNgBWbFF?0Z<|$stsXr?R%3LPajRm5{_RGlw-FqCs>C@*UJC)^$sgNx-ezF4Sbh8=b
#JZZ)Su@Yv<%kXO-gE>Bbd>#>Ep0_{l<n6HbQuu;z|nuXl8m(FGxzX(gD^x>%Cf&UPoNGJJWXe$d
CLtiLmdbig?KCg8{ItrLD>UvqD-VZ{fX6Ic4oF0EbIlG}%)5kcWD47Q1X@;C2D+Kc*o99H*S#^(~
oW>FAP+<?ncR>L-LrO|gijZQE+ap;Ab-F3(0&?Qmc!b|lv4DC@P<P3C>OA9H3F$bQPL;yCZBLs&k
8hUgN94l>Lw<lA7`fZmm9Q|ancT9b?y03Zv5)|PR{=IgW5fNAP*qCo{wXp1*i2KpYm_trK=4WfaF
7>!h5c!CIW4K`p(hGGSs}3S-c|2sgA7{fpBDje7>*E18U|QEYfEt-?Fd#XorGZxTpBi2VmQsB`w&
0s(g1#4yb3hfv@GHhR}c{^S}dYfXjSpo7ggDHYXxXqg3wkgLA6k)_UXRu?L^Uf^fgA|+o9>S8CXi
+hI5JzWQ6@PJciI2b-ErdLV0M%;j#GTq%ypaP_zdS{Bp!pB)nW+UBwHR{G1RQN(K5r3<}i!A~gyV
AT)7WELP0#s4uj7xWiMqT3k)DXkz3s!Wrljmz=ueM+uK)(BB8>z^jX$pU=PhaIxd6U~sEou}1JTa
Mkl0kGT8>Rr}nijlMh->f38^s7GdZ+uIKS3H4b2LSrR>+G8#EPj_E|dyQ(Ht2a?TBAFiVZq$IdeZ
l={QWVp8gknOJsuGXw63N7(T9<=f&!U;`n>~3`>alk)#0k5jp+mZ>p<z`zax|6|Dq<o&rUKv%a2J
`!Ptg02wS;B;3%`KvW17J;9Mu=0`$)r*jvqB+Ze77<*Mf%i*{3&LX|GcQjGmHtvjuATj$p6w@?7i
?zBo%oHBeoCt?(Zkwa2&}7`X})+%h1UimGGMI|%LG<On2uws+TLgtwAMXh+b-b8f_hhtR?&g91&Y
ga`m@KOxmrkgspaG*N2PUX_aW4Us8#;3<}?y0cra>bi&WiQm0xxAG*jfNNeCSrJX;f`=Rb+8VnlC
-hP6KOfN4%&<fQr54FtRAlpI4WSUL8FFR^Try-GUHbTEoM@U!*hIdm#@?ue3hy9Yv*Da+(8(7&%!
rXxrx{)(qgIsel0*CQh|izXlarI+$z!|&N~6W9dl0mq@x^mfo5pkxTBt|-;YV!kHujD#m=!Em3q@
&I47!K<t6cU9p;Y=Uyk1Y4wuXFP^(^Ri8dSXdip$JU$(iRUFzKfDUcJ&}!nEPh2+>XBXudYBkai8
VT&>=IbsNxgZ8HqCi=8CB0+hh2W_VDQr>6>~QL6FAZHCkgyQc0Vn00TTl@2nzP>%`d_G4jev@*Wn
tL_nRtdRfsvL-LeyEG1@IHP7i*xMs9Ns-I&K2Eb7gqUJ{gD8(C7I-(jngW}Ga?U)thlyzciRyOx!
8E%I4tP-zDd@gd?2JNyVlR04(|NZ^HUaqYaibaBB-b}UK~x>V0zL!~OHndC3JzOI+Ug#_eD0z-wa
qdWkaSl03I5#y?P-vK3R<fyy9Z)8aNj-db(+C)ug6k4f4m{X6#g7dVY5eU1w~ib_>en+IV_@COpk
=6#_xf!a9Hqa8eQjvu?U8EHZN8|KFx}T*U=%JKov6E)eKRd!9VB>1*aWo*soz%$kb#y+`}5#3q>!
56#IgLBf13`$?WJ4Oq}M@3`Xk&Ik&y8y5Qo8!?w(_X~;17EAbfWlnaRSvyOD+@VFMCl^PA(4Y58Y
oyhF^?ujY#51o-(YjOztMYqy$x7u$PJB*CLbt1r<umaQveit}i>~LTBNUa)FBhXMa29kSnT<qvBv
5W=NiyfLAKBW)zgqD*Y(I<RHCJpce|Nd@v_Goc^`S{>*c&j!rvQ6PF5yh@c6tDH0#|;O2kW;^PiY
gv4T+nr6BluSUAE9Os&^5fqhdp|DjSu(n;iV~g$t5lN!<vZE<h}@5xOZ?8PQv@*G4I@?^Mzqo#bO
gELJ&TG0n>q_1c?HEgRY7U^&=s)bB7okEP-)33`p8-qFE*gzHA&<0M|Bg&KogFN|&?w3iT}M+`%^
-WSO3)^EU3yJPc7R@2cU$?BzS_;+g~yC`{u~2u4gGJj5-+5}JTwQmp3jkyjk$Hh_l1zG4IL8?ZP>
W2CSJJ@y)delzIzTiv1cTpD5K<OnDqwudn0vqtP3E&*znsPqhZ8|~uqJ$e-E!)gk#(2s0p*nk0Qe
~ra2@Az-UywSD{w;`6G;xs5n1cW)E1c)U|^M%&na6zh@!vEob_$EC7YP_Wzu{s|%jAr9<g-VP?lw
QX$Vw*XqxA)fDyONIm>WcUbyh4CE>_YK|I|;4vnSSK;8IX2@G!s;8SkgM-N>u2ZA~=4cF7w|ZGzU
~1rlh`fhmCR-F<bH&cKHpJdi_Ie!-!E8ZA8=g4N}Sh_dhI`K;g6#JcE}Nqc%+dcRC2eC$Jz1!YD#
+CBY9}!l5Sw?!-VF(DzBBqC3RVEjoH!*U{sOjvhCLP-p-%>^**5(dRfrsRBWE*zX>A1!@MQ0QVMH
uG*#Ptm~@-%j3QucVzvc5UxLxQ}q=v0BP)@w}#`cRi)=v*{iOSOz!Kj25aqaz?wOLagM#J!)M%q;
`&S1FCI<ff-J2DgRkeZ1kC_GclmSm4nbl+MzkAOp`A3UWU4`kBIdj^_=xK~@4{cgg+0QBj|La^7!
k1B#ulxr7OC|=(rOLv)OKV#>HWE(1Dxf@FOAL4Et<IBs2Cs>y5CTU2t2Io9LeK8j{d&75XcfSBE1
Z95F!QwlR&GMHjo|J8&+2(%@}SpvBbvRRx=d4rvZI{E!5;kuzS>}9(<xE2U>m%_w+cP3~L60%I8Z
xQQ$Bx@Aa%v^-PWX;`pGiSe!l`vcoE#NH*Xf<BT2=Lj<hQhwq*rE6HR5QdV?TfSd-O*uMhLZen+|
NQO2T?Mo267RwYZ%kjDj_=Wf6Wzkd@N=gizN5CSCqZHR*na6Cri>wwmCg#n2xB0ESg>GkYfhH3y?
d8Pr@)D6+06$fTI=;l>u~#nlwFTqG@MSLNYt`)6TF5CgTk|Mc<j(C0-6VMhfPVLTL(xVJy7<K}(X
~r-+!Bt2LdE}GeA^aG7~hnYxG>9}8u=L-s>O9ttw!~IQ!Tjvb37UIkm|<i&oO1l*&#K-zg0|9H7k
atkqP^MJlM887(#4&9;}|rTF;%CzG`?d=D(1aV%Dpc^J1<`72F$c&2K4A>)*m?&2c?KfOE4!O{gz
lfYmCN^JyGz&u=w!=Z$UK-kR&GZF@Vm%j<3}@AWy;2o3Yq_#@00DaZ_~QArI}!Ly^X)@zLof+mU?
5=CsCHCun2^+Tk#n4ntz?H-3povmTq@Y*Cvm+}8qTxR&kxy(ilb)|a^T%+B9j<x-IZZs<T5uWvUw
=ZWi_1#!&=zzSZx(Z-&ga=}Ug_L~>AP&-zWmBb%V0vi4;9d_j*-~M<JAgl~{!d{Tto<jYf32Q>37
nKt@VorAy07;%`>fSRm&q#4w`lR9TU(8<F3E}8Ax~oVo{dPMPfb>^x*q$rw^!y~%?ZX=0L)9)TmY
z-e@y+)BFL9g{&Q<u^`Be?TH%i;4(>B%66K2wQN9^XKRm#hlOJx%c)}>sSO+XdJ_Qm0?A{*I4%Mn
_hQft$1$2RRZJX<YEpG?>ONEk#-@h&>-6!A`0u2(MSwk+>1nz(@3VivJE0iQmLMryc6+u%W6G$Kp
>#6~yH#jcUHDV}#o58Xf+%|*p6kfY_yo~2>K^}<Fsh)(r-~)jU_7D(>YuITGG2QQ?RRDoFxKmb6x
UrBT(>Bv&gnL41m_JhZh8zv`u^HPu|84;Xa*|$iI0ht5UqNH5_>!bz_#oRqMGx*JAR>0io(Mn^xb
;>vnJ5ELx^j{>vB_jXUVrGBKTl$dJaKCohK|6V$2W2OF|XeJbU&e}>_UAU=xd>&+7IRpUj+@<A*e
Kb6Xj7+EX-P6?2Hr^HLUL1*D+o`Tkins-Wh26*TqP(HCH>O5jL$#vQeC8YO4&J^+#>R(JQsprW$J
W-M$sVa|_n89fyqc9s#MExlnu9O~`QYIY-wo11;mDDJo)6-*vt~f6_a=pl3x!hgJOe6u&Mp07Hj@
GSJQbUBl)eS5p6`w*IYG|3=sMSmOGjEUDYzA@;pZ*SFLSl)urpsl2se!)V|PR?Xnv044%Td$<LK4
Hp;-<MHD*^mT1MUaF72jRRS&RPZwADv-iuRKRY``zFFfsQi$0=mj=lK&C;$F1V&DFemNvZtI1{^Q
ATiY-^8Ed3n9=rTqjQd=x$4d&0n&Hu(irK#fi1U>;S)2pDW<S~)JoCf1i&KOoy%d+m_c6)c>kW1Z
vr3Ie_DOXe8H2HG}|K^r6sIL}ZQXUL^_dbr-e5Sw_Udf`gKNt0-0*%=C6TDFELhK(#em>G`aCv!t
qa>=A}c~~|D2BNft;$&!h`zb)LS#Htv!i+W)THbEgO6``YM;X`9uLc3jYhT}BUD*m>;D+snXM8@g
yjY^O4=_y_?q&t&{~~55b!KT%{hpH}jiNf}dy+anhqS<2?M|+LN^dTt2*ygd5ZDoS@O?Z<ifrNf9
Og4%VW1F&KgwAnZxH|(C?i~yt~fLld6hti0HW!175utPKeinUNe@3jz<B(4kG6$_64rB#1@LUMDP
_c_WaJE5+9g`Cb3c#A1*x;cy&ej`Xd0(GA~z(Gj9$q<X9_mf{pCnEw%L)3v5M+FoCK3BW;MZ##{7
^Y?u2@56sTi8Gx9J9t-&-ksG53E4F}oYfOv{-WUxGAkZj=qL#r_~9bx-1+T}6c_@Dy;;ET3?BRg*
pgrTVIfc1c5is_>!AwStZ;hK6#IM<{{Kl~U_v=K6dV~&`N@7j)6FZQv=4U<9Remi(?4GiQy!Dw<r
8)wsOX?Rf6(o806lfw#<Xi+v_MKwpr)Djlv?j~#B1GY#bM?sZV6!F2-?;eB|3LRKfiCwa`7#T6H8
;j5*iF9zVU)6>JnbJXmZ2B=l&m@c^ROl#2@Fk&#bHo$tO&@2p6$gE>!}G#A{0SSvN#GOw`}=m<ST
m(=?~n-c72*R2toqz3-cs~~^)p2F^0TK%m8=QkcYlI)hlLfWCL2f74QC?iBCKLSplrgrEs^5Nvm_
_t<PcBGsooD35!$Y<Da9AVQm$8Um^XvHo_5-$3u!Clj?yqy*0Kt6{I|{Jgg(?4blC}?S}bq<C%<B
x3;&_Sp7Wk^-x~;!y*wofgrbkYTikU$q+uvmzeA~#2Uh)_{Jap1)vq4}uMl#^tCVya>?_4HYX@&Q
B;bUja-qKC@!_5di0MQe;1>7xd(Hj*o@QZKslr-w((EGHpWa2Q97Qt@Ux)SsH;Y)2dcR3Ap5{u-I
Vm#%KDIPFbcJygu?N%-T`%Gl@a)kvDz&(X=hK8$xfHnb!*|bv5Vi;EvwC}Yoz{5_T>D|89h`DlvY
bOFVqm_~l(X@8x<s>vM=DevP@oww891b0<0#F)3MSFwBdWJFXP0CAF6PUUG>uC`%*p$mLriAyE1O
E_Kh+ZI*<m$Wz^<uKl#v8ID*VRK@*Y@EbTUTh{6t3ivt+!;P%EQ?80HAyR6>A8mzlJi0-W34l_sO
TqOgK1f@40>i%YwvVvi`srs@(2I0h{n0aKHt6cWRWT*xN86mft9)%2BjbX9}Mt03wvVkj9e=D?x@
?*kPI(b>%?UPkxe5pt=IgZ!V%IR0eo?%ek7ZeV>#b;t;{3_9&@x83fvd;199nD$k06^+eh$pVADY
QJlTA=t<Z+-@v^VAmIou4B#;uS=XKw+(;QfGVom*pl~_=%{)>uc0cq2kq#cbZYAmo)jGv=>bB)g8
>s@J$kkj?<j`7DW>Cx{)6s;|D?CCp7`^VahN{BJExO|(IUyK!}6>3Jc86Sqbj#)jZdqp8k>bnix)
uFdo#aa7el8tS48_d*xSf8uw1!@Y2YrbAQqM9areNjLdXHc!LO}oiBBf1iP%O8n*k+?6T=gF*CAR
#g1nplQo1!!<Qq%TCMcDFjl&#o`IY8Oi2+t$O2ruau?&AI6%gE|>m=Duei0$iSVTUSiU{<vh<vn)
{H}rbAUGxq!Gc0D!MTGmk(!>03!T3bmLo$IaMIkClIW^h^KXFFm0F^1L5Q{ZD%WIk7SFPU3QZ&r*
C@c8f!U`Cx~FZ&j=N=CU68m~@@SnAuCM1p!!0Yma@q??9FR)LzqjX8F$E5V)@vR38jgMh<G%(v3~
awPE`?HY#&%=}c{1n>2U>EHiyr;WF)rZpU(D;2B6&w+z}ejB^-<w55>yW9su_(@T?Icy$|a5lT~E
<gfa{6gEJ<}lcII2z`+XAU<3%#(fXfuA-BI<^>3$Ssc^f-yPm%?85UTIdWsZNXAz2oVV+=Vxi3*C
Kp{wA=53yO4C?#ANYv|e(Q+cORd-ga@Y#P#Nbd|s{FlsbvJMzMCsutq=Broz%58vn8C{{a0J2OSF
3zEF!lmn9;0ktfyT8DU%2;A0HmEF%I8v|%@EN%354zF&!Ex@D28^&xb_mljHObfDc!;g>3SMubpI
zUHSbhR4-4P;Y9@v+9$h*MyhF>rmz4dNxYIULVcc@fV}?h|sy&4M!U0wgMdP&HiqZ_$Jr9*jp6CL
4p&Q|x2W?=v3bEJuVYgp%7KvL?FZ?A_#`;@ItfpS^qQ_IS5Q3h%1w|KacdJ^0IX>L~c__p&&pF_#
;t7!B1Pc({*LJ5<l)egiMy)gwBvc81j(iCX+m><el@nW!jCY%1L|PDL#t8a3d)5JMm;VMm+7&|An
qqy)57mr)gAq3+<^B#V<&eHjiM1K^6easr8m3)QchT{}S27Rm#H+K`7i2j@=3tr!1iWT$~?LCoIK
WEG4nml}&CgP;~P06{OSu<`1qoyYOVuoNsyRuSGa!_BcGwEbT;TFw{9VTSW&u$+%D%&SX>-c#}tO
fbPb(a){r+;JVb<h&C3jfm{gvbf1mpY#)yY(n{HyvTA84gS%Z055XWw-Z!gx(jMS>}4c9g(xTN92
IVQiXe;@GrAsX(v=0}U*P+C%v+(%`6zisJ9y5CD@5vVB{`-)5TirNkb#OC<Q33*sKPu4I$t#@N~L
iR7GUAEz{SqJ8=XjO7SPlIsx_+Xe5$O26`(iQbTgCzSSv?Vew1DQ8Zu%C1Ev@8hz8ZvQpgditKF6
TdvqJaIRf1MyXXIHBCY0{_qVk%O_QdiX=&gUBA|`vFTdOtzx;ygr#s1KfrgW;8*Qo$ld~ZoGprfj
4*_NwVL(8|yOl%ci8`B}aY7Md4)Fpho3|*4c?KwqX=0L(aqx2QC7}V#3ChT&dR7$KjLK54w^;jX$
^rAVf>KW!^=M0u9YK2|xQkZ70xx1Ka0C6zZE1zVdN6pb<)u=Ji3dTkm`;;RMJiNz<@Up&D!Z1K3|
%iKX$7M$I>94;HE`tIVQv4JST#JH&;Ynjqqg`mk72|c>fk^%qUym8Y>|5ComggHS%gTpVF;2Jx85
DxZSb&taAkfm^;L~H0Y2#%reVoJOtL%~z}ebM4oh6I3F@vaK~gD}bX(50kvZeG-6F?hB$}S1eR4F
FtJEC5=(uIlr@;e-4|G`B>ci#jNU;YU7w}rhai(YKBV>~0(1%=8D)2R0g9((rFcU?pRW4Dbs%}KB
Q96~>RT>SY!c)idQ*aob3U&w0P0{q4m>AV3g;&!9cuEGcR6+vf3mep-a@;yU@1WAI(=PdG_{diHh
_)mXyPy@^+Ev-pN9_QuiSe$GEWfBulg0}5FivH!8SMEC>jNUPw}nqt4KcN;m?ohri&A{=H^)U<NF
8s2ZVT~x(&TTV1d&urOn&gar^b!QxNl4|rEsz^{6R8oI$tr~Yxz;H?15Cn(t0a^=}#U#oY=p4Az&
~(9vl+<Z0QPA(LDd?RxiEAcqSa?t%Ali%Iq6+Zg<;?7Qn30@eaeez${G6J<>qY`$(Ram;oTsJ~J?
j<|8B`6{r8PAv1_jVs!+Cg;T1eb999$=m6+r&i`M2QC%?yV51^RaC{90yfhs3*<GqUM&M*M+(MCk
OD5l<2qdAE+;H&TofL=B9N2~FG>0KTZDmxg;;dOJMP?Q@AJ!WVR}VMR_^xyeRvo+b2kGA;q%rib{
K3(-`xTL|Jyhkr4{Iytf3U|1lC_PclIe6g16F0nF;d#v)<>BewM*vZC6CSj(@r@vPN$A;uCeieBT
kVwO@Hm7gQWlgG`GlgY-R5>xiYw4>$z6ltkNbw?DQt>$%H$RhxH4uC-|SFb2HfIp-E`A$cgh+S?S
uxi|Zu@5q(c@LQAQ8Wb%EcI^`#(e$aX}7Vb%$*Hhyj+R<b(ilk{6DyNymIWFRVE|Y~Az@Q_|bPgR
=q@Uc_BK3|<0wc-8WkBmJa8>`Lzep<z0qX7Rwn-ZiF5-C{ktSvqFRo+7c{VnV2Qy;s=o!%>F$G4L
Az|Lw!g5Y2V@SspUq#Dlp(N7rO@=4sQ7GRpc2@l7(>kr8o-SK5@cqC&XJG|dExZJ569vTm=J|0zW
(VM;^&b_mlGe<piDUt_4;fWi`hbRWayF%|=nr<5o9ju%4f~p3EJZ1fRE#WS_ZgvKr_r(^IlI_VE2
<et5S3^q4<|~!2sDw=5;iX}lGuYu{RXGzsM@rgG-;>^!_Ms+plOE2MYdK>kJr`8S$1V=Sf~aQCrV
oxMjR8g>lh<Q(%K_8R5q4!NF{YH;rPp%Q58zH6f0YYQKeI(s=7UJ6?5ZZYY*sct9Oudi$^dUYV$}
<>j=;PI%Itq=-94Sc1k)S)bop-cgW!&%2y5AjzZgT?zzP<3l{N`*%vc0y2?Y@29B&fH>xceDO1f#
LjYf=YbUgY=H=v()h=7x6^kS<%cP^G{8%ecIR=Ldv)y-0w0I4RipAqmY-Grt!y5<e)i6RDM;WLJC
80NwItb}&#SRF>AC6>+nSo}QH)w09;WhD#)~uB=3NQ)B$Y29hVUq+Jzd;MNJAi6i;4vCP^|EQtpv
iU0Di$?`yG2$IEmYOzAWkro3!=hk#2nOUgy-^Tr1hD6Okbos%^hGP7C>T0$ol8oq~$*03d*J8r_1
a<*gNQ`Lz~)RMRbI&3(+*YUdAdSXbWGHyup&m3(7f+h(~Ur(sqka=u;@$y6tr+^ih$)=DeZIERuq
{xXV<!Qh@#vS0_yh&XKF^>F~5s(#vH`eH54(ocRt^Ds$@7#WHOND#<TW>M20zB0WBPae9iS=F0`@
ults?O+u4#C(TtDTR;FPkj!X)KWEEel8IO7bc)7*Y>B3%Ejkb_6GzlAU1d|8R7<Ozbf*_7^@^EdV
={+qwH8@cSSgU%O@BHOa}fevp78P0qE%4Vg(z*q7~f{WOOW>{M*$k}1ux_LW0B4Ib2g?UId2E=#T
1bTtzju$5NEzjDIF}r4b6E#iWpNocycn}F{#AooP32(*>;iN1|jKk8KtJtDq9wPIl?Z|r`OA5@~n
M{e)<X8Q9dFm0wJT?!<WIMK+a?f$%5kmbH7hx^Y9`CNhHIt10QqA+!EiTF=|5jlWD@}4UsGGB72s
{(E{x=vsugwh~Ohf=m--!BT8nJ;U$<P`8cEa2G9;LpHudSK2CWAGD3vOFPIGB7sI)<gXcug_jKZV
Br5F8Omvr^BUh6tOZt2O<dkTh{Ll4Xa+so~g?7pZiNt*7Ybh)Mn^mw%Uydu<2JPU?&RCP+;b4Wo@
)-lm&(g$p=W*`&9&{Uy66}XDo3pbwjUuFP5omIR@$zpsmGaiyg<PcKk<+wOoQtKoo7<dK_K9S4vs
ELU=#5tNhdjDg0vyxGz$d0<#^V8?AhbvUFlZk(RVC<QeOpg?54EyI3(@!)x<w)m;69Mewzj??^UM
AP{F^LibN2~)!r`>uv5}2T3?vQM_%BaC=tGO~DC5&B2t{`2tN!9iL)X0g)jgbZRSOMHnIBhYFYLp
o(9^R=G~7o|al@mGqnb*mtKjtIzmQEM+bISaJtjj)N_&s=b0JK+h*p@bMGt72%wUhdH3<^3xdh*P
%XCc@OtTgd8f`(q`G+!$2ZYa6IR>8wjt~htVT9mWF%Bq-IzuZUv88H=D8IEP$wFE+yVgDFg6qrze
feZ-sHF8;Vqoa%1DVYL=$1Q;mD&b(7s8=0!YYMKXv#Kk2G?<hi4|9NgG`TUx#qA0Y?(gCBb@|y?=
_N35VG+0AK&0Jr!i;kjS&coyD%f<e<>g166BW-QDZ*L7?+wrI(a7`{Lw8F4fEB3r^@WBCvck5m0|
FK)daajR1Egohr8|IEmFN?F=;`?VnxCmY<SxHI&+>xr&bCM{op3bZ>Gtm{!W%K>PwdEj|)>JzgZT
^)O@9gE#~XWRQg0MU!<pRU!MF#xmWz-6bE;De)48?^3(ar+q2VmZ_m)e<YEWUNild3jRs)K+22mz
j{x7W%x@@NOyZH^sHp5{G+&L;QXW}Is(hUk{OJ~WY~{?QDL`2%a<TLOeK>jX^NZIf?dPX&xj2h7!
H?M#U2;!TjuL@c;dXw%NZ%a)G<tdR{``9w)ShFRg<B+4C-w;TN`>zHRMv&~NUG7sK%j~h6sJ|*sK
`-S{0wiPKVqF_Ora#qfHGV1ZlCS3+g35UxRPD$g5@?buwSLMms%6_F@Q&wDuEak%oC<taYAWQV#T
t}S#i@?XTar*L8%yB$a_X$L@QTP4Jag>#CW~t^;B&!Y{i7P`ltw=#)cWSWyJiJ5#?mDK+=@s(<=8
zHP(4Hr{vJp3Fur~BnJR2qoW>SN*p*KoXi4K=swIhIUy@ilfet4)B!w7J*Q^Rd1D~&943pU0|SWQ
GPU@5jEco1JPPc=p)DF-pfk4QOO&zl;019I=UIkPiwMt%c~*y6TkD9wfZ?&`uT6MfItE9080Vp9L
Bn@c5;+&=(<}=?Ccdr+R&ubb?S~w^MGdH*fHxn=q~p6us2m|41Rvv=?NZp{1wErfI>Y`KHV0h;e?
+I!WC6^_WGPN?x!i3aKY%v;s<{YHEld*=O_2du5#xY|m|P}94crOZ&7D*O#*C*xkG|qAQLJGe$El
}Xq?w|0fwQvBo$z^?8sOtbNpYo0B{{4%m+AZNYJSi_)QP04ko$p-NVt~)wc(6k6gdJe<QKcxM;_1
FBA=g;)j^zY?g~q3`+PG2m9;01Q*(on<RfMwLgwI_EJ#|GjeP9l_P`fq3o*QFa5}(gDhTDU;COXI
`qsvvJG4z5{Uh7f{_-fyI8ls{k>)h1yee&>aG|j0MIpe*OL7Cs&N=hFAbBEP5L+usREk`wgZ4~0w
nLsjffkf<namLDu&=!U-YA)ef)H&|&Z=*&f^)oF;O=Px(OBfNl4OyQx9_6q$I2mL(Lo<Aa&scj;e
?tZ5ggxbAk-?nwT;5SFwyNAz;B{#Q#I4&9Vcq)GW4~RMbi)su5!FsYU$ZgpjoLZ<7hqGLD}BJ>;(
--XEV4eVq~S2H!2rzY}4N|P5!xzJ;YLs3bpDY7QGT6a$Vo-h#qR!NW)afcI5Y8>O8_Di9LwP3fqc
s#aBqY1KquuOvqyZ3IBD5UR!9?Goimk7Wm-xnR;!?LB5?JHnso<q6K+0jgg5?#nYSgOyB)*`jU+@
q?;86=0u6EDPe20Nw0oJrq{s>YD?6sC~S%G8@BjWE(+5t?X_-{k1F$`5?NoL{&<2pwQn(I*GJ^Gt
l_|Hzm;K&=ecU&7iL@VIt{~={GxPMduV)|=46q)dli#mGH$8vqaM9se^$I!wftFa3g$7m#IGtMPe
fhCUlUh4W8z=FLa*^cfM>``qH!-exJRe}rEB#Y80j?jqNn3UI-+surQD1Xn}LNC6;K!Me2mc7qGZ
URQzR}5ij%qDuZpT&6~h-1r-=*XAtYa(7CD8_<xgGxsi!~rA$zNtceDN~8w&O3xTWgD09JD(x#cO
njtr{nGvUI`le;T1^IOkZ7JGnmCpQdlS91T(MXJydscDX6R8x;k^$?pJB@-{cUB!-sHNNG8Y0W-!
4r2~ygbLI)eGCB~|7SSpw7!X2SI4ba!`}{nZ?q5})gYXqQyfAz&{<^5dDv~x0*Gn!Sklt7d5@YM?
A2*JE<!#LDwqukPL*lx98oc&o$PbU<T|P+@}DzJvlA`x*>Dwj7<uDSXv}feN?ezEfX61u@KU=0s9
j>@25JSHwM*O7L1z%w(%8_t_FE?_b8$s`{L~7%@36cfiCYx*#5!xF|2FY-VM*i`XqxP%s)uq18~o
}kr=h@(c0sIXa;yl-yT&(gkO@KKDCHo_s8*-%@`p{%<C=4ToNCtE;Td#s&20+<;c?s>xl<p6JQ^Q
6@TrR$_28@oCC#9*f!wh5)Mc!Aw5pAHjQg)e=S(z~u!dJ~o}!2^=n9A1bQ)X(1qzlfk=bUi$>1(_
y2KhbU8@pR9mHg`no#xs<nGXYLSO2-+2X;JflYa1C>@%L)v%m}T?Yfps8<=$|BncB?qce(Geb>dr
eS?Kwp6o%+~D7N&FP{PW-K?QDwH4v97^pwd=5opoAEBudg>y5`|f;n{NwTY@dr{p^J&YfBz@gz6c
X|%;2Zq_uk?YzObfnaoyKT!iZ=dHN-}+$)#^Cl<J8y|i0&Qa9Y$Suq!V?2O*i6vw|aK|>WpBEck4
N}cb*hevb_{!QBL{#>YTaEyZiT;QHXEj;kc$+{h-~3q0xy3Ai%~)Z;rn^eL?AME_PnLdrN+V@DZ6
_`S>2BJ65n``Io0>?_VGPOqNDyigUl;?UIhC+v8wj9J~QDDJ#bMhx1ph?!ogDX6tDv(%AXw`RfzY
RQKSUE-Q?xs!N^kPmW)n;G+30>{2a5Sb&%99$dzhsnMe*Z-02*!pKVGZ8On5NYtl@?Yq4rd}0ibI
4e6o+6}tm{6R@2N&6Mu4d7LuU-yO>CIu7BUfg#&{L6O7qf$pf&)HVk1lAw6*|;ZU#vBt3NJu@ymA
9Ftwp1#DWupQC9hM!w&($Jm$5O<}{3g32q+-l5!O>BGHk(V8cYxz^$Q4q?Wu5q-f>vNAVS2~jqt-
$zVTL*5cV|9ZTos8NTO9QFhgwOY5q)j4gKS}fas*)s+nYYdc@E)-1=w=~l@&VkJL04_VOkiNu|iN
9uAea;>kZ2y5!LP2-V+qOxk~fXYC&Xf7%>d9YPjnXo`|^s)sS%XN)<iE!$v3xS34G2Uu${CWELe(
8rTHdvB<qCQ#>ZGqz8uQA64#lCFnA0s?PYjt1lvjb=PH1Ajtz_nIA3ZK}&WmlSIB(rxQbpL^>>u^
r-dHT=piqB~t+wHL8Q^SLSa}p4ki*qk){VC*|fa33h}8tTYlaw#5I7dPW`G2BArN)>P_u#B02wlH
$OWV-^H&81k~QKIDy&Y0CUA_f`=lro4Tt`BTRwPkQnz>2MLADug>1E7$Gr;e0hOF^MLi16gT#ETH
xFX<(77njAhgLi;+X)K^2l7v33+pV7i`dqTmxACO1Qt5+}fzIoDvQ=hNG*vPyT(~r;-YEqr6t8oh
}wV)Pl1T<(O14K#cIEnIdusON|uMlE*6+kR)%aMg<@qC8i;pO0KN$E>kd~8@{Vi7vEwymv`GFV%x
vcbmI3!(_Rd-56-`9oBk60pcRi(NDUvqasS9*xhVt9Znd3#lca`}sRa6L8qKu%MzwL|A6PN~+sZr
q|9XkHI!bSCcO<!^KyFr_cHqJCE?n^k4tuYhrC$@Vk38{7PvO7%;GXEI%Hv8RU%eT?RTapZH#JHS
oxI$td8!`$7K@G0H2XgH2$slM&!*NO2p)Uaow)Etct5%EXC{g(lWvz+Tek{L^V-*!KxuJ5dQ(>u8
-kV~mGBVOC$CQYc>V^Ok+$Kp(`C3G(tOXf`Hmw9mw!n}tPvMN8I=csS0N>PQ2=JswBPJTAF7Dl<}
^5gckHF_XP(O{ORXJ>+A%<ueZY^^P?g|D-bRe{ow&IPai`6heY!De5}`Vd*+9e3HNEAjMo{4SnjB
#CBDT8z)D+sutD_%Q;sZg#(_4(r|@0LWRWcb!Fl&pj}mamfgm#f`L$+B=@EZ74B7OVZ4;4d3!Naz
1jYKCD&!AU+hXIvmINmA*41hRkrw1AgCi_#uKh#N7)7<O4Xj6Cu5G87p>4V98n$>&Bz;;Ia1s#Im
czeAU$OK2>+BtUpshBTq$FSV|Jfip`}%ns`-k==9MN7P2P!-HqaJ}K-aijU42*Vvs!+zeCIc)y!5
%);R)?{%1bm$EP1-EX+bJjDWl1#b#w(Y&O<SGE>lruPl<}CS+rPb^E4fZ(U@yG_gFeOHhrq}k>*=
edR-mpW2geJpgl9TWoA2|NGg=5Xg)ySlOeZ8juF&%15?j611T5XuPx_=RA8S#ldhBB4!v}3mcbEO
R#K2m^5V2#si20EXiY)dDPzYArF$_MnO(;6@9C3TaGl#xCA{7CIFN<}8NCmwx#ex6ex;VT_A*h>l
VQU+W_G;c>Tr+JzR_fE>wvw9*W1n`yRoL3YADrBNqgthqy|+^`;{%)3CSL?dXYk5HG>sMupsirF*
(3sx=u`t)zJq1q&+DzPD&S~7$B_MK4?4WMVkW$#Gj-uE7RU3P&#p7;GnFWNs%^wDVl@jvM153vb&
UXz9WNy-XN9=mD1NCU$x)_Gln>y0ohOlRoEFagcm0ZVUS+`<ELPJ6Op!4Tl;7i;g*idO^RTov*d+
j<$qT}->or;UV@~Xq+p9`Q$e%^n4%{givtP`02;Nkkyem$j}O3T?3l$24HqrP5HGd6@gt#vmNN-8
;GVQpM2Az}A|qcp*hE?Jg$poHc9tA`)mVS2w}>Nk@2=qJ!`SCQlDLQ%j$?+pu1uqS6W>pgYdEB}e
nM)~WVv3|fm0v<l|zycepTr?F=3-l?MU{~q*MPnIREa$BNt7Z!LQ57HRWR^j20DB>B9QYX*y*Nwx
)BRE?H3d{xgh9H10SyO_esWSd;<NlK$urPV(5=$u3+zkRyk1FMZi=<h}u-#4^|Cc~glYFwmTKI;<
E#apKz3(e5RSd$};{n*_5666M7X<Z!6cnoRNQZ}yo;v-rJiZ?AAtm8e<<?Y~8vqsED=a{rWVr60h
)C~RWU$9WTvS>OfZrE+6j#116{q=~0j?W$e9mbf}ngQ`=`g;}*-FpVUl1n(SkpH*E;PiSOS0$7D;
g<THgh_#w#w>gAB7L=^tepAVB=qXv&s5qbMS$Ft5pLxp5n;RHzLwp{HFJVtnbSt!v9N)FcpkMxUZ
W2OsV;|V}P!I;!&^R1^>v|QEE1@Meun(b|rjTcJL}5t7kY~F$tePyXu0RNxkDlDC8)4LKvpTlQpP
v98d3JlSx?`<%*O6T$j5rfPWHjhpCZL*QtX;bNaHc@FAbWeF!>dZ${Jqll=sL}y+YkV8_Uuv&fjb
iyoU5#rU8~i-+=_oFyMwRP(}phbXj*n!&EOPo=;?E#w$GZ8n+QMDK}D`~yj*ls;|cCp?{&@CT4B@
`*JYepKObxNN?5BSF63ogJ=WLT)-j7d1Bqhe(u|d2Oh{Ym`ktP}316hAf1Lcev`i^UH*X}{^%#%h
s*S}?#;P^n*H|u)&@H6^ww7+?BRobv5+^Dy&@@lv0@z6XGdM`)TKq+r$nqh$9@Lu-jV)Nv^&L=Tk
itu#YkTk1FYJGwA@xs6&6h?g-im4CG`<VOs1B|h1_DT)uJggTiB@?L(P<OfN*?^#<*+werRrU)Sn
eC#k!{|i+a+xzy`~^NGR`k(Ufya2$qYSD#gJ!_6ix&{47w*aEo?~5j+C&Y;tV~t(7^NxDXkJTVL2
BOY!?h&@E~~q_B*VXEw69LvlMTugJo*OHQ@S>`3gIt4#}GA!*|bjIiuM5>8n?5H_qWay%xqEQ`~!
b>|LJvuyqMk4O%<KfygyLGA&|^Prb<Q0<u~vl9{Ul<6{9?7s?5%lN<x`Q-((BG59*zw|!OajM~W^
inOS#`fTH3>}dCh<}tt)zLq}vA%5G1b5}poW}jp&d$UYGhDCJEM#L35@K6qSq>6B=KRd-!o%Bvv9
>c3aZTM{r_3eMVK~;5JzxH@B-s^>?vYTbq1f@Z4TI`oDF76M%0r+2BEYQIG;=UV^p}E`duFMK5oP
Ph3WG;UYr_b>pzH!#P85}l)gJ#g-A780%H~jMW+{{FgZH{h*hj}yjW?k)*w=YE$#O+)g|E^Zp6bX
}q-iZ+8;&yQzZHwDK*qdmtN0?4~>G^jb;I|hX+re*gW3Uk%J8PJCgHFG{KV;k*^zbv5)?b=dA?3m
>QK;P&dkU-d{rB(#zi8Qbg?f6a)Q`8Em|L=Q-#h%XAeLe6O5Pnt{SwHNtE+8c{#+5LX;Ku^xCQ$e
GYTS+0whF(`<%iYjA0ll23JAS!(@jpMeEGZ&G^IKW5DG7W-y>(pqkb(3OGet{dauj)Oo^nc+74ks
q;Ecuf0mJYxbbhA?+XhF%=(RYWw_syf~wP)=sr=xLVg68&`WFIEg8TD0Hh`^`OU9dzDq+-(&@;IF
fN60cY2Ivd0tbRMtF0*uEnZE%w8k#;l}{;Yf9wdBOwOuWp8ecf+jTqkQUAJX{Ch57`~T3Wwp;`i5
)KeJyS=tD=nhIbh}s%5`m5JltOg<M-1jjTSGml#&-vP=h{GDT|bcdwYlLpiRNBWX63sk)u4%#tGS
7(#h*woDeQ@6hPD|?e%dF@ArfK-xb3&Q7POp7k9S@$Ce7cop3ZyIV;h(`U+NM6ybI8Ax4Cjy6*d`
^Ou!j6)#9o#={Wr5t^LSDX+FslCXwE!o?EYC0XBNOsOksiDWBwR)H6E1X9y{)54jfpcC${QIfkUh
GFpZsN^E$1TMNn@}%rgcQA?hK8Rc<QsP=k+O*`&f(C2DdY771PfGXB3hKK&CQAq=nD3T4`2Kt9!h
$-sFQCBnmZ6DsOZpyO^EIPVavNS>61~)hpC&*)gPk-VA5+vf(QSZ<c*N_Kki<9Ew*h6;u><3fLkv
f>3`=;_a8pGoly(gZkRL+*(Gx$>B2AeCfPRhpVmCPSlp#2dK~(e!9Q(tXwbT%7l-R4&)2|iw>{ix
2EU`3YoNqe&wV}^U22)MLol?VGNiQfou~>^Q!76<znTPFioWR1-;`-JJ_Oda;uo<o!Ygh#_w1XD5
gTIS_B#tpE7#u0^F_?N#7pCK4hb<&XmrbIQzMix2UNy5RezA(2hqCYD8huIshaIJNLvC~ljGNI^q
iNr^tdgjC+UytYn3lL1IZD-raiLAh+Ck~QZIi0%5MdkR8*^W<Y6Ukq;t6fn=eFUK*T)vNVwLG2Wf
YWbW9vZss$)g#vE!8va8iJOizAeJD6-i$!K9tgXHLX3Q5LdpAn_ugZ5lF#Mx*m$HII)HikYBp>NP
+r0;X+hS4C3W4DE7|wM}hf^oA|KtOn1)*~l2`vp}Pw*w|xD7V)^qD8R;|B0SsX(9=lDv?PuO2ohA
<U^)d$lSizfvf^v`fn~+R)(UwdVbDNyu?pDvdI=n{9nr&MUmgV7;#F<sm~(=`aeHw=2LO`9cDpUR
?g9=trAo4sem@9InH^<eDGIFd$9x*)Hvy36XfDPCXnThJ{BxNVaXC{D9CXo&U!pa8fJO<oF|BMnc
!_a!FyK!_F=7fBrOXvu1b&2yt%ZXh-GsyQ(l>GpaKa7wmlic~b5Qro(M!bbNdA6xvGY}<Z0Ag^i1
D@>VU=y8ys8LpV+RU;on@3>jm)pyFui@ph{v9FO}8d~^21yu(&HGk$gr19IB7_VMF*h=k5`NurEE
%foCHuBYn|{mYAEHvLsFt<j3oml_2R9Bf0For=ax^4zF;YZsO7j(wQZsa&7*Pv+S>ANKwV{~qdaR
Qo-R2bl-m#$;(mFloucaDE3zO`9;XbmhXAx46}?)(*f5J|Kcxg4Y6)|9#SmkJT_O+eb<2S$0~qiS
Br)n)dHB{iGB+AE(^HuU^BWbipF#rCF2zq)xI6+belJ-*F9~DaLyV4{b)}tS2}<C-6h^e+0_4R!%
05!IiN?Cf-*#0!#M%bvb`Kj#vk?uUt|c}6a!cw$gN(}USUXWN^^$o*ZzCZR+HVs>WT9;yiaxQv^`
WOa+P(Dxs5@+4!fWTbM0`DBKqHVZe;sj9rX!9zMQ^PP;~hIrz&boLsyZ)DMTulodqp`os%U^8(W1
$N#L%IXV6VzWyzJ=mfE=Fb8dvP2K+-^yfXJmel-DcLc7Gf#nvE6h#wsjm6zc~(A7_KO?UCU$-PtJ
fzDCn;N%ce`K`z-8$9QUr6)CwbLbKl*(;a5da<y9Rsud8wHhF+%-m9Z&G`pNc?1+P*TN7h|#tGl{
hjL1E8#Qq-)&~x$cX*R^ufA90%?Z5p_D)M`OLH_~gpuRz@$ATY-QSpFNQK&xt4WDzhnubHyq7()t
CLS|9<FK*8QaiAgQ<j(7mvX<4Rp;Vm}-<GiO>!7LpS(?_O)cU%*M6@|6C(MOX*@83YO;TUOaOgh_
dBhRcb$p$Bz4j2)b`7%VG8+06ENP!agctL>tF%PH#({irL<|jbOIS3l%6-r(eTBj-LCVbzhHM6HZ
Mmww;^&GKXosuJ-J-TUJ<EnH*$0<g8z3?<gTWwK^}Y1RJ(JQ6%dHKq{NP$fnui90j_*ZSKa&%-Bw
4e3NB4mT3Ad>JSh&c;O7NpBBk{8m%N8c2JP{iMWidB#&J*lh)gQa~L?9`aw3bK=`#J8owFLB_7%V
8oWg4*fyI-$#rUFgmBv=LN5pKZ){k^=7XN~QOVNqcYkch<?};1n<LLFx!*_^%Z5Z~&rKp&9<BVw)
Cp<JTGvawTY`sg-lMd1_Fjm%@Ai5Vktj(~sb_O$I-h6@Dw?a}IOn+Ql|_|#<7S`J?xf;8Da<4?8|
z*7t2R3AT=J#nD4KSDM81^F`((Q$J&F<_nONx&%V1(P4S)hxf!zp|zdtfeECK)$BH!;MQS{s6uGm
!SF2f)t=)iS$lPqATBQ~W(%VFr21}pQd!Ytq8lHY4!j@^d!xttFap4&DthVQF7ySTG2*%s!p(%Ib
g8AQ%Dx^{z%G`t9r`YjO~yX%smMU2pq?U7`ZzHGp&I<6{#OO9o1Go#9a;@;U8jH)d%Qp(}JgXWbL
48w%QE%vFZFmqJw>oTb;MCntYNcGWPS;dUE(o2tl(yoDuHjLMVjUNoFOKXGq5*@58FX6Gr9FEAYr
){dM`_Xpkx{jQ=?CQ~EllvNYFySLdGyYgv%x&H>t*b1J@)Q=Xxf;0GA+7bA_p@TU_PsWYtt|6<1v
^=`U9<vQ=Cy1>wY=<J$5nYUTT(O;2lC^zb@k=@^$*6Fl+R>EjaM!0Ii|eEn(QuC;U#AO)A@RjtU(
ZH>&nknU=maywI4mqwMifQl%kXgEz$93BbxERt2+yIA84{_GL0$UW}Rb9(u*BQl1DX#BQNFsnr1P
paot+zR!omuMVZiPkt=ekmg)0A5S(pbIg7}{oR?o9xS={Nl3QI;xvJbjm9hJ@`l5`?HOZ{SCFrQM
uVrDynir*=WlGoQl^9I!ncR|X!d<gvER|06uB#X5xR*wqz*wi2as+sERX4hutvuJ)1l<$a)M~Y^l
I4YuY6}WZV^#CK{w?j9*}Ux7y~fQ|V-S;IK_SX|0~l!U;rcdM8&)qiSy}^+-_`yP)wH1;KBdz8L5
0<<(Rx}$$q=M+3&!+U63Hv@X<rq9651NzA!a=y%O&p_8*x=<hBRiFrXTqB@9GC_53P=pt1sS>Mj^
-h<hMFYgE=z~&bl~=)~vNrKq&b&>EXtjIPFqRe7LEm0Ha?8pSn5<Sp6yh*4ARHcOK@;pUxk%NNHM
7@0FL-zLGDYaJTm6-Qqz_Q*7!}J(%BX6OpSeUL|2@%FAD?BYJBU<HO)_r$f_Nn<-a?N9EX+51lr=
yXU&dKPu^vO5=IthGtL~bHvTcXV<Nt74_uATDlTt;$5xUA3Dv*HBDcQ%Q)h%iEYEw%guOJkrZ8VM
C;R{mo$#pS{t+Ig}R5Pl;Y&eX>rumP%d51S^1%v0o6)Atv?Oz_0r*Ey!wHT!sKaPoe(~L9hLGnXJ
(wD_VOvj$=m1w<zSQGfEd+R_Pv*@h>{X<Vl`@^X}BUy0P}{q%n~hOzbYdy^kQYiQToJ?G_1)4MMe
5ZL+3k0DI?8Kqsy2qi;seVNbYV-40QqKN4L;IS;K@GSB+UCoz0!7!KPi^v2J)^H9F*|8K~uI)J*%
$dqIQHQY<zI?q~WH>kLJU*r-fJJe#xrLk$R1gv{m^_!XyD3;%>Ol+c>?HQ7+r8g-X5%GEv9Jq-HY
&an2Djqid>x*Nl8dbCduAb1vZJ8PPykbS9Sb;iR~?IhDe3-brK*Q+9vVnux=DtV&xW$2MRkp5Pe?
}j&bY-c&iR{k-!(q*tD5mOqT<y^(sKm(UWa?P&Dg=M@#nK=L-ucz5%G|j_?;PPlhZ!lG#nPZZpiC
>iB?K-~2j5uS*|A`(C#K><LR7di1{Ng(7$4Y>sqjYcE^wXG6EyiSJoQIkdQBObJbNXraz`*b&#&I
*r(q_Qv(m2lEG`XB%pqGzd<pI>3w8u!LNsoF-9@omy1<P>0R)jl;p+3f|77PVRrqsC(3DcI>X~Ky
JWl5BitL4pu$)OK}za`HD@_fa>SL)g}4Z1ycs%P~&ySTvi&Eq(*<^z*$py^3MVGE**6fmo}xmr#G
P7-+~c4d<#nYWo4Ke~_8B*MAkd3e2?!YpBUblU)JW0Ww!ym)aNP3ajB%OVn|I`rJ3Vc(Hq7s2Iuf
_6=0y%xa{w2&+^d9grJlyEF;gf50rP72Sn=8iM!&axc(&68_bexToJfvz@u+s(d%Gr4ZVh!6-X>c
fmeXViT4;rPwT=<M_#7}<KS_vGO4B7JlEcJ$`>`~~KM>|La9e|R%`@%=I7tL!~K;0NzNoW42!@bl
>P$=mPFzsFZk_{G`Di+68dy03cs-&~~d_5AqxYv}Cw)yetK@c3Z=BK`h{SFfP6pPrwdW63Tw|Ng_
t`G=Dee0uito9FLdQxhHYf|`*E2bj9@^lj;Rw?{p~07{RKU!Q*W_T;7W{0Xhh>vu2ycK-AGlhNth
AEDGswumr~e?0l{{P_IzO+bvLc`hw7xXj}p-oAME1_ph0M(=39zJGUidVc!u?da_FJL);y>#%><9
=f<3!2jr31K%IR^8@()%^@ZWfd{>B(7gQQr}GcTBN=vR`;2wzr$;|~^s`StkLl-texA?|c{lmT**
8u6>2~D*uKeGV|M%qoefj^f{C^<1WR&Ij=yI7%C!=|mC%BJB$j9g`fy(Ou{q(=a30dw2##^+@b9E
?we2bSEc$T=?sqjTP=MEW=7<(F45Sik82Q}sC{i8=g&+Vu}xuj}zpLnhzgM@+^&_`@;h;Gl_;OSG
Y;>8FB_AAz&7Y=?rKR&}PSq)AuJDy_R$Jd`YoI`j*PV-R6nCs`cT@pRm9Phn1XU|(4JVWeh@e*q-
-H9mmIT~dqDPOJ`QlfluN24T7iqR-U>wGt`58pjcui8mECqW2bdaq!r?#j_q7!iQt>MCATzsyJE+
i96F;ZX3hpS-kaES`&s?u`TEn{oLHu1hkjQf~*U-q1JvkmkyoB^49Owg#fOt})CfMt2=b@`)zUau
D(j_+1u!iWixR48{hGupsT~d9?g_pm9vE6q^Jym};aU4g^m>UJ;SL8x?EfPD?Q*Hnb_213SF<;J)
lA7@8%qqe67ozSh1yw2uxO!M~uvbqEsrkNy>q&kR-%_h@$?z%Lhh8V%QVyB5iI`J6HnkJB7@RKfQ
Y3)*w%EDT;7Pq|#b0*5RxHtb&Jas08a59F)K*|tJUVV25!;sfc~GXV}a?=CF`R;}s1VuzX$VR)S$
bF8Ihc`9Jo67a1fF76}U+HuL^s5z;3w+iD3to~bB2%5D2PM~*NLj4<<RKA+YXm098VzWGUmn*zuz
iIQ)VTN|o<^c@dO%J7?Veu3`l}zv^_joiJY*%e~7GH#zXtG*mk_2r$dscU8NIg_5#43plf@TKC2%
La$#K1c|X%@@s+ZH^1aQM(q31j|>UCS+8r($Td`2jXC^)Atgq^O<%LXR?GFu)uCmYKL~nhYz4Lc^
_D$r>w08$EB@FpUA!9hPwvo;p|>-Bq84HbHPGuwfp)=Xv*Q&v_bt-6ouJB4lFwLMjPtktY%O+s|b
dLuR6cT<mgp$VB?p_{9+y@ZT|wR8+*>owIp?m(My*p_(UgU?q?---E{BBTjxZ5+gKVstAKg#%ptP
CcNX6q7JZ-%ZX}01f5dmXeSl|-6P6O%(Sd`G7~c`^N#yaFQ>MJl!B=Nu*GEij2FFE`5+DStz#ROU
tU{f;TUn$?qo6tCDY~1;qiG2Xf9L{a2z*<E=+T8RNGDRWC{N%gAsSs|6Gg6X&hal0FYHA92V|J&9
-tFSmv1pg*tNL#KNq)z8#rqs}38rrWr_8aOC79y{ftMq^XseQoVRW<z2ZdBUYkzK2F>x&ppLnIcT
S8wc^i2&bk$)0%ZokZjMM1yuHk(YD3eZ;2|5PHsP1dW%#e{CW+sF$_!iup8KyX45tmyeY_E~HCi_
VN4fET2%;-oJ^HiAYIY1k`Jft|G4_ay(Fm+o`Isop7Fw4hdhG$dd7#Q$Vx{GB+A_6WOId}GYx<2O
I-$Z*M36Oh2Uk!56R~YOt?i~}#Z0hw(T1WpknM{r8e>hizKRWzdMgV-AG`f}@ZqKxL<_r*0eujyN
L=f#fnN>b`&<lLzXV$l;kD;SJsFmMOQg8Oo50i6WjrDVro^XI@ix9!C-K<C<uuC9JQ$B}3TIn~b7
-@30`nDvzQvmitK*4!?DJ(b2{a2${D;psI|Eh+jN(FH605c7uhlj+MbSM%8q<`>79*ygzR(QQ2ZV
ZhWLLqjz3wKx$r7Zwx!jR(<$&V}H!9>;m<np&{E+JOUV4^rL3GSmgQ+a+1a9#gsc9eZD6P<)(S^#
|mle+?3QhTiW<4FC`+|#B1}(JSXVD9sjY<#sE@!mh#ETyCGHl650VE-b#89Cdq!M~u)vqxM11^z&
0Z`If78qm`Z>e~(I+X?TA|kA)9x|MNBZePhg?k?`u(7ZOm`Ox&&)3EQWx&9bM@lFQ%U34NpmbZ};
|0RZYsXym?4k-D#H&LPXiE1hjmlLYRWw$<4I;+KznSqHjHbzTN)S|y!8l6yHjai0Gk}bg{*!LyVe
8*FgIjOM-z%DrB^sMHIZ_)XPoblT3gnYl5HD<SaF3_JZHb8A<Gj^y{|hgFlkqGrZnB9r1G+gJsj<
=MKmEr>kNPk*gI4g#=@suxd{xgaovcr`P>W%!vMS{H)l~PCK+y|74g0-e7JHpWm3maLpUxkGwkEP
FQ$h6sr|MN7bd?8{R4J{p>QwC@Qg5J(EjhNa^+|*o*;yd*_lPT!-&6R7MPB$C<9ocA01$a2{ZyK=
qj*&FEZekwqQC-ADo*KD6%<W~x-}x|s*Y*8S54}Dsd3s5l0`RjJh;Q{2KN{T*X#VJNB7NkqwCgy?
o;m%t(>E*uA~vY#=iv;w~eh#?AMR2VrUz>G}J@%YQ%&H0g)hjnyDjxr=*obpTeJ1;7v9e>8k`l6q
A%}Et>5A$GxDFDVzAPf98aUW!vV*e|q~|oV7@MM^Tl?P(y4yR7k9aN!&}WfG`MT2;6W0dK4USnGI
MlZb*a)O_%@}lZ~brr(hH%9Gb8XQEEB%VTtc;&N|mx03hgZvNZb+2KE(Q7z-PH#v{n%_+y3lBN<5
%1IXhi2hICvTu_b$HdH~YOkZtTVtUI_;9XwPW+`{=m917#Tk+*3x}Jp#B?OX^j6Pn@LN>-VoV1%{
5Mx8B2%i*{(Rqt55~e`yt(zX9qlI!=exHH&%eh6Ioa`gTp@$_P^3W)Unq}m(Ycttcs-*Re5Am+Wf
s3i{&ca-5@-Uv7Ayo&3@VWYa^$kvmpq7jM>JHku+4)QT#Z*=62Q~gCziwH!S~Lg~(q|mtCDgAqm0
bD8SEdpfC+SR@G|NzS=e0J}UsT#P`(ex3Wlyb!tK5j}UTa(N$4dA%DzZtYYFV=7uH9&>B$!rROj_
+dt6Weu?~)L>X8o_qVxKMdIVM{O!>}ww{<W;gEv+o0jJj^CL9ns_>Y>|S<KKeChnvTvX)~koVGS0
qk;6-k`RKA{NiYap$-1r?lnwFLt;43JmS#8TU-8iUX!xkZP5N42ge5WM<8b@6t)iH!t!mL_t7~f%
XOvW3t#_-oLm}Z!i8CCm{_(*dsYzknZT*6;3~8)gN(~Dwb8QEVN<hpgP2)x=C=9a2yg}#w<Z!s|h
*_%;GKo^Q0-o#~27IMHWz$mFVrN-dTvMB5o~`NRCR+G;Fwi~YPO%L8wgfm;6GNNsMnv^HsbVQAD^
%JdmW(zu8<mGur-Cn}b$gACJF7#{vx_z--Qp|`%d0_$vQPlRkkRHAd%IiR&VK*!^V;cEw{zI<_O@
xLMy6c5dnFMh;G`9v(7BQU;besRuA|DssgjY<b)H##N8P=<Y2TEsFk>?OOY2Bis$m8F1JtRpiS_w
1ho*gc*N@ilXQuqKwR@AiQDQc4-Jk(cly*H)b{c$Y4wVh`f!WQ0&w5h!EUU#Wh>U%svfhu}g==eL
+4_6?N@zlZdiLw86yqDi(m5^sHK_3B*Z_UIwWF%~{f(?m>1?9&=#MZqG7!0M#(ZGtlZ3%u@irpK1
8RAF?ra}MyX&#k8h2w$s6&g|tEP?-CiI$8IAdpto;|Z~fU1B=l{O!cJR*H}CkIM>9cBZh@$NRK@1
ol*UGa6)qwc?PbiJ)c*IP5X-j^QT+Jnt?A<>J7w$cZDX<+<(2KZ`226;3y4ISSRt_7lYug<u-&is
Xjg(ERagg+-kxeW(<{jFls@SHF(Na%@9+)yjnYtZdz<8vnHG`wz;i?H-rjT1`p=(Z3L)(nNG_*s1
$c5JKN=3l>ewkeL=X7*Y8WVVjjsdK<NPF=eB%vP0tuBb;XA#croO`=RiZ^#<PQTv-<fWM;+N-AF=
V~=}_15`lttklcq!?UUZ{`N->P==DUb{VfSPJ|psvyF%5uX@^2z4aL|lga%0S!=xY3`AGHX$JXX9
2`07_*R{s%Ng_2AlZiKA%pho=5owW|GI&XuHa=6QHOd01DMTlyZVITn^{*IOxu_Kbqhw<0DlAJVb
~;F!sgGw<uhQiJv@>Pu-Jl6U@+0>TF!R+{{`UIS^Zja)ppdkN_ul^Zj|`fs1d%1+Klg7w>^BSCbV
95_Y~Ty@H#!JLIxVyZs2RPH{5bqu<KO8tQP<OnDWQg<vguLePRfXg4TLi;T<m)d{(KW`5e8K98u^
h7D>$I+Ow%nAB43l;sTaXpjEnj17>vXeP3y~Y!ji*Qroa0pg8+^1@LPWx7Fllv#z$LxxWV8$7|cO
JXNdemc!G}%eR$Y2}+Qo;a5FOSIMmfC+}L=y_!{*<`i~=gW=>=@pjCu{Gfl8Tjcp_-iP7uLbYLaZ
2lN?c4Dg-gQucM^`0Cr7i<;aT=td-iMi{pm}*6UKRS;lFkcy2ovR}>D6^f^96sxU-eW9Wg7f{!;h
G&Pb6kHGt=GmympLB96$)_rt>)05P#VjItqpGmIZ2mx=9!9#v}BY|k922GHQd+w!=S&Es?t)EMPq
(>_6!k`^bG3BZcx8;9ulf4(P=ns7n#g^|8u8E>$qRz!K4@Hah-vJgaxp+##RPvPUWhd<W|9hYsLZ
Yc%Drt<)@2X76UP+=_{j}-GEffrnf;q9hRz%WRhuxrK_^$DZMp@M=g3+QP(!TsHa{Q87l9Ds<Y+j
XoIk}-s8Y-)^<GDs#V`pp~e=gLi1AQB&Z}E3Pq+;pYD|Xr(NqU4sc_P%GlB=4|Pl`Gl!$jeYXSu+
-&J=cITTW=KUb_>>A0Fq!G-cWRYWdLvbdyE$!q^Tw1V3?$0&Nq>!Fqkrf;?dpQe<g3~=@lRBl4a#
UR9)n!vbC@w~WA*G6TW=l7s%t40~@2$ywH0+p{l}W1gyxqP%8@=5lHH@}n6YA7<BkQbRxsct2948
fj{SK|=L)&gkNATAmbX5k9K~QN0Ebkz^kYKm(IVM1$uw!>7$(;;dLE3R<ssXg?-DDd_TE?cfnWU8
Dw;T&@kz9{Bbg2~)?n82IGRV4l4B=SJ*xodnX2FY-ApaOo<09h}Sg+m((PG9y;65x<OtzONfcDR)
F(vE?fBEH7KDJtDb$Y#^gn6yjd{x|J6n{?-2cBY#!C!u9v^k_42F1YueI{0%B*M=1Xe2Liev`~4x
LWs{)+MG9f}WFkr~At<7b$!YMhy$>Jy8V+vwr!7P4Zjwc!6;iX+FXG43o={=_@BUmXJKNi<DA-VR
kBLK?4n2;f!Om2)XH1AbF5m9Qf`O=J+iJ9h}9BYsq+%Q0VIGIGe=<S^{689c@Bnijsois3|X6N{=
zFD(;XdT~RbtjMMayBfxRq6pVD&CUE1^pnY|DPj3-cU$H@S``1}cp+h;+C#{>x*htY5DR5#G{BsF
%K1R|D-XxrJW)9pgS{Y;Z7K{>jcM}zu!o?(S;iZ7>m&Li{o4v*8shr>}N1Nx#swufmaa<JlpH?;c
7^mDUCG$~HU%$#>?Vys1<BEY5B%>OleVj@FJR<JE+~5rw6-o-(d^Euy^5|NfG#VQ(>v6Ev;{MEzX
tfXxQMAi3L+|(|iLdlVV36BZ(SueCIE;%O_(j+x1%~(nR}dPzjwkdr&04Tb>LaWUf5cN7(-sfy_<
hNY!WUAoUG)Wo%^Up%0~*N3e3e^OF6XO@l;DfyF>HGt$g3YI+b(ApKUY{sVH1}CoCSwnq}{emF^C
Ze7ajgcg)q}HX8rB7JA0k|!(c{s@R*<D0VS6Wy6wZg05f)8FUgReR{uaX0Si6lfWi2U@<PCZpxa9
amhSuG*Y8F@ygfZX8@)gIFnWVdZg`2-f!=~g!Co7B<dOfKym2mxGywU}7L1@x+=z-6(WXbpwu2uq
(4@*Qj0u6rARc!b^!oDT)w>UGM$g~9J)yXJ>QpCk63pZ2ZIW{u0e+ItlQb?p=-N-x7<B;V`we9TZ
@Mi{gYh)FO~zBFv1zcJ17!j{a-YKJ<I+RiTcvgvmF+Gn+g(((yQpq=isbS7#vQ>pnqK(>rBu@Xm`
ZgQrMe4K*E-oL$Fn+vG1oJ>V&`rAI8Yzjlv|c^Ok<Sk-Jsha;>per$gf#SvSg$(bm}ykzgdy7o%G
O@EHAm%=~`%;+utb4YoAM9$CHZi=TPJF9?PJ(gjIg!e$-c$*$7*dINUTH!(WTOmmYFNJ4$+O2O{I
#N(2-t=Z2KJljzC>A(?2CphI)xk2o*>Bq`%5>o^V0S0OUo2H5PN*B=g@t||V2Cm8T^3Zm(#RC(M-
fh0I*Kvni7P#l(BZ=DXh>pNi3*K|NHKdXb15b76Gj{ekzL25YeFhe39R63%gL_QwCiVRgaXH~}3q
_DK3d>p4H^d^w|b~ex3cQd~1#uOIWVue0f1)SwM=I~;xP?N+~HW!7;AK_6U*+V$DC+WBIBg9Bo%s
HkClFTi;{1r|UWOO6Vx1qv>`5BP%7kEO`SgYh4$~6i^d5d(J0!FoM=>)-9BNyGCCYM0hk~nXp#31
vSCh5l`P9BARTslLt#D4GFA!6`Jn<qo*dv(q_`k*7}t0FRpXfknfonr+q!3qenL$;fC-F=;+Ic@&
_ru?^v&(``7Gi0^XrdtWgb#52j*f7G9l6Tz~ZC)?Q{fj)I48M&a4Xy4hnVMjs5-*gC$nsGsgM7q#
j3Ue>fofvuMlDSRI5)wut!`xiPd~glKL6pvNoljoP^?<c5IOr3Ga0Qv{m*12S98|9E_0wJ!IQhqP
H2D0>BJc(lhkFFNq1n<NtCq+w7u$cd)4N1*e-!BQZQ0LxUJxzgm#&!t>4FPUfRz|9APKZpd=Es|G
Ah}L@ZN(lbU1$X6zjBU7w5tC*lb&z>%BiK(b9y+P&YbR3(_|!7J(~PZJ2UNXA8IsdH(Lz+cMRR^G
J~Uao$Hp$Rw-=F?~#Ll2K|UQjfT=U!3(Z>6!-ax^OdqfTkXlWS7{sx8Kchv>kH2?Na1uxxb`-Nu0
ueQnuEr4+yp8k})q-KyxM$AU>z&yW-rawt8Ujj)#}BE*tGU7s6@;HYc@Z$W+m5Fns2{38bIMTDj%
L9ES2H!!Rb29D?K9h}A%6$iNp!<cD6wPvNxMM*rmkI4&prTuIpZa{cVSoXU`R*=eL)-Ijvm<fbO6
5=U~lRM%)W3tZuj4*<U-bIUv^-S#q;2e-13~ZuWL1caK_-B<IFAP%IRhYt#d}%i|&V#6>+HX$Iz6
TD>#weaNP{D_Ah(C05bpY;clRlGKS>7ImqOiI}t`l<LBJqszc``=FT9uFk$IO$H^qN5M@Vm)mCV0
q&3?gD@BYqh2A5N2QX&s3K(5o_|W0DX`(hfC<XO6M1LJ)=~Y;8QUM<CyZ5gpxt054C@PF|n9IClt
8#mbaMBD74ek~EGx$h-EjnTOjXz8g_yXU#U?P;PPaaTkNmuyz8pL{`fNueRz#V<T`~lX8drye(-W
NwBe>(=1Cb_4;BNv%U^BusI&ZVU9S>md8EYnpV_=VSY?jspNbZI;k?hHF`m05kFyJ(xd3u1*g=~6
;h<uCvIT{6v3{DFY};v&u>4$+jel48QO)U3|i;*!uw{h!q5&u>sb(fqQDKS28Ad9E*J!MbTP~<{S
e=H7g;tzT1o1aX_l$%$TmA-;}URui{yR;ve^{ZsqR(#6mvf%#YzW$nK2EsD;O4T#%V(UTSDB)@jY
Nn8|GlX+}mGPyv_N6+5(ye4BdSid6||NEfk@;W1~{MN+g&LdYnz10gO#YR&FK646?7hUtb=>zEk6
p>;)G9Ra6d&1z!hMinB)Wh&tdx&7d2%lpV$_nT+nqIvEFyF?gwSyW?FRT-7^lxYzEOrdFn@?wY2$
8=5kU(KLYgl*~hCU7D({wHSI$aUcTG4%)}lL>mAgf?P9@cU|>vW!}}?jGOgQOQEY+DA``lF#~7l@
<KUk_zT`K58K@<d)tsAG~@++*xtJ;oog0`bE@@i*1RbrYkWBorbTK}Hi{Fm4bCPw2CmV8B@dPO=H
G^rPFAa6iJYJo6z7plDJ{9G84wM1L>JXMD&~GS*g?%%HJN0S7TA>u@ljg|@3wxo6m*LF8R!Z_%0+
<RZpc?R19(!((-8CS;&U9o^V}7iRFi$=0i$4&Tu~kfWcaZCiM~eYW7;86q+B{Vhqs^Vm!5+T#llU
R<BoQLT6B;uBmovZ=7i3&uu4xm&Dhrv(?Yjc|IJ&2{j2hSqQ(#lwe^!F9EcN}>5+m@k#v1i=8?E}
X}!_5?L%1sCKR^Q?lg%sckzQ)YmyZqjRQ%M?$d*Zu0tpc1dXTnwe-_4ohx|Zo^iPXwU8*bUrm>o8
6-dIdAmm78r;z)$7{IgI>K~g&IMr>09!MiiuwmcGQ}t11)*jQo+AdqcnhmF%(#}TgBq{-rg01JZz
rln%su7a2g9NWZOk*i9|g3{1BC)e+b9y!#O!zsx5Su&*TV(Ig2DScOp``o)VaA-ZW9;TUC!5f*TB
NDOhmZ}dDyvZk;O8tU@9y^QA3ubGm6`E6ii{*p(-Tr@QQj)q$Z_cQa0)3lV!w3+G%_jQYvlY<Q)w
mb)b{CZ(?lx1J5Y83{Rs^JUdqs;o*_A|6k_dv%)Wp=@Jh_T@sr@msrT@xXn%$dBr;y)ts9pa;~7-
X2n*+6T*Uz@#<(A%`PVq*}nAYHyqQALEr3%p`AwOl*DkrP$CU<Z<k$RHi9_9xLZskCmC$*2*<AQC
11{Fi0puwT`QZ8dX4NM&!9`Uibx_97>G;ShZ7!i571oA8?6f_09ymKO>VdoWppFoP#MdelMvZ$cU
)S}qbU{k=se>f>86M6Xfg>0vif}8qZ@d{145Da!^!*C$1hGSgI*iS=Fx(^w$)y#<<q(3DB<<6YPj
4wy+@o=oKXg+UqbdpPNVYJ+D{-EsWD(m=+&GaX%(*5o=APAku%#x><a4(knfuCEiosrEOS*TThrc
cd{L$e*e0<&lLH~XC&kpSurq3o1zTUmBu;EzM1f?iI0DYUOesDmE56sxvS~ZMceyA<^bBXPiM1H2
V~@m{-*mk`vkkJ^#5infO4zn3<r0H2T<m=N;K767`;+6BCm#a%$Xc1hUZ=yK==F~$AI?tSy*2NjS
TEncdwFukuPkjYp?^~kB~F(ht0OaBF(@bRoI-yBlUyLvH2F=NiM-+_r8wOlx2!wB8xHX0v0D~(Kn
CKd3_moj1-e$mi!{j`r3Zmb=~_vQ03?3cKDb){i!s~_+ocxJ(gTY+40D<`1qe*{Q97o-EBX7$qu@
9dEJS}-^7oVcz0-<dTJc@8<gklRKAaxEc9(93Q%|DlNMk8FHMiAc;ojMIT0d2J#?|+S6TWG{wW~9
2ws3^}upJ!nh#ijzi{*_W(&~Zf%jhND_4!t*7Tp=uf&)<e{Pcx|$e+V9&>^5f_8Wa=)a~;-v(4$N
&saG8%<oE7{oilS=(>=ZuM}vE&>WJ?VDm5VJmnFJzMBka^i{9kYRY=y^A3s>>DiQ!fD6Fh*t_2g8
-~T<BHOY|!#~SlsTurN5SDl?Ypcqrba{K=GAZ|z_N&Ugl249{6`$lb7Z--Sx_6??vG8EPZ|L`My-
Tcv7BVj3eqpCs?cjT>i$-%@vx}JK&ZY%}es5U1=u-3XI2vo30~XGBLckLa{YaE}POI{m6Q)<wmcF
ARsZTwHCI{W2eeETUb@<@u04bCwU4GJSAe(KfTWxhKct2?kL_=w%#OQfcqqB*kPaLXWMcfHj+e%r
61erg4YAWQq*PmAUlTXzB)32kCypEP@BqiI1nq6J9yP>9nmS$BI(By%=P^9OtQ2Dl(w|obnl>cs?
bA02W$dbaK)3pJ)Y&aVensZD0r?9&c%Uc943J@)5x4p7QTwxXDFMhj2{{r>F;?PUy#W|dvZ@+t8!
THRy>FS!V+)L1rce!(8pUt%lEbrU+5E%OjU3-;M#ZwjBZhM>WqG3QF8Kv>UNd#uK(kjQ+EN==%`$
?HyXG<S!X~4fb!=XCP_;}yWfxUFERce@L@$YS&Oyt}i9EQPSFAxV#-oE73Z`9dM+<A5rQ9e!*dWM
b)coQrfV4W=mKWLL>Idpr0hRDp<(11{lFHapMH{V&)-K^ZJHgN^vu*a*~ZEt8d{G$lXb*J|iXi9A
sEd!#&hTgf_!Y-ra%Q>4l=AmaP!!HM7C_1dNl3|N-)NrLpirE4mxTh<!|F7~->S<Zb*!#(&<a%VR
)oc?!e<TfMH7lC-Bj4uAYRa9HDp8sXEcHz`ouIY75x;SvYx*wFh}+@I$%hNZWminsT%(cEtAsfd5
FD-UYe9i#twS?AEL)mY$s>eq)%wbo$u=P%djZX6D=Pu4WCp~#)1#8Pml>59wG3Ub)6)w4(fC5JEr
WJXD|qrY=B=E-e5}sMo)>r+vhW#YAB`C(3jpV?7Y6bEXx!7%-WYiQtQ|XIWt~<a*|^RzK1*M<6$K
a_A0WeeKC}nA%rbT#PzFGFNgR<z`i{L&$X6uDZ?Yxu+Lua>pod46F@&++Vtok$z67%9l8m)N#{?@
8Q*O2nCn*^IIz`yhSqe4Uc-yxK-7^u;7KX$I<<yU#O`HcD+GF%sax2>_aZ8g`X}PuYOv&a?<70@g
;RtkwPTECzG2kf=4N9_kdZj5`JutNahHqF^hIa)lX+Zp3jmH9KJ`!;8RN03J*P1Q^l#yPpW@KxI#
g2kav7iW<QP2%OT2jyzNtCX5)8s`qpW_D@W_AZW+y3KVrVSpry_q;Y;ms_2DWO#ZVIz<P`i9X5bJ
w>iSfZav8sq6^n-fo`Vh#}9hn6M6s=}(s6HzNnk!nvjIHRKFv^WADvf*8R!q8~QNKgdI<P0YxdrC
m?SusW35nhy#{$aZZr(lyzUx@lRbEgzIXuOBZ-&Ae;L2fnv$cJ4Uk!WGNL&x4nEO)BRrwln`>>>p
XbzfmxNeyjeT3st1uGAzKCOe@8-sP!x-o299SS8~~u3`3{+zH4OlT_;U{n^`wR&2knS|GQwQI%P5
nbHFXNPA=?qZ603M#-=+k8a~pl#h_zLCZp8UTC^=I6kZ}QFO>DQzk2GCY$3vFw@BA(*!l#Wp=T`l
D14%8V!d+pn;(V343*TxM1ny{iUtvCpW_UVcw?R05Ui~-_F*sB;?8BA0B_un6DajDnc`89%_BDZO
!@I%NKtZ0$_F~fcb{iQAP;Uwt*{wOu@BciO|J`=Y^nR*DBbO)76MfVn)&|0P)rHpGIddj$dPl%hw
g|T3Uc(ADG|lo2aHXQvJPAML(4|<PO&{Cg`w;kzjgDMDWpwZC^*U1xF+8v49?Hz_1k|OCspb{rmq
0SF%%Q
