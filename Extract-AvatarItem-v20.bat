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
if "%RC%"=="7" goto :rigfailed

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

:rigfailed
echo.
echo   The items were extracted, but the rigging pass failed.
echo.
echo   So the .fbx, .glb, .blend and .jms files are missing from this run.
echo   What the extractor wrote is beside this file. Its own count above says
echo   how many base maps and colour tables it found - a zero there means the
echo   container held none, not that any were lost.
echo.
echo   Blender's own account of what went wrong is in blender.log in the
echo   item's folder.
echo.
timeout /t 30 >nul 2>&1
exit /b 7

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
        # A pass that ran and failed is not the same as a run that worked: the
        # .bat has to keep the window open and say so, or the player is left
        # with no .fbx and no reason. 7 is its own code for exactly this.
        return 7
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
}+?FC=v;DSHG&OtE%hq`&N7#&*Rx(k`y<s>2j+dY(4nPqeU@$beU$4lI%8^F6TFS);rJ6xA4Cg$u
J)!0aptq@OfMW`C=aASHTfIJSvK0{w^MVY|ZmwkY@8dc>C<XS^ywBy-AAze&#nxFiDFd&8~xSntc
qe@)<qsy$Ej8<gQO&rT`--=J_lsf+QZ^1TjK}-$8ty{Sush|Nha3)A!GUVV=$7G)rc|-A!I3!E5Y
Pa5>JQdYF!aUW9GN!SDu3VLxB}<LBlupG*O8k&MnWDp~|L`FMmqii68^-o)0EQ9u(DyvgS``06H^
CD7htJPIz8;Cev-g7ZbU-PsA!IgDdG&hKb|=NSxY63>HlG94$AB%4FY%cV?GaI~1kK{%Yn^Q3shv
)SYdMFSue$@mI7GR<c=v*+1;lBMxCMes41Wy$!_eLRs$MbrrH()kU|7z`{J(E`n2;)C(0dstJN`2
haON(T0l2TdAk@WiuvPvIp``s;X{Jj+K|I=}oan84Q-d_d68^Xw{}O<;8KHB4|Zr>+z?>2wOu5O&
|_7>o{I)54hxHHD$z%Q%At(XB1hWIQT@PN%mY+$OVmIs{yJ6m+|LJHdRG#@Y249)vHGiK@}*_PSV
NXLl!}k-y7}be`r}0qZtN2vuQfo}IjT5fsq5q!DB}BNgBpw2sSsm0mAqNxvNRB#8@nQk-X<*8bxl
9_LW%J_r|6nEp;{w<C|1jiB9vzVf$EG@Rfv{)j*UJ+9MR=x&}RfIZn9P=9iHo&gE~TEVQu8KNFE*
9uNyig;dz@obhtrD-y2;tVAB@FD@IDRdQQ16#OD((4;UoFYHZaC-Gz#elEVykOL$b@`Z#lX;#6Au
RznvKs|}sH0hY7tGU1(h3j@CYNK{4d<Dj7uogL-vp2~39=-C<<T&=;bWR*P!y2zCWS2v8xN<~*aP
Po*8YyRd@Ow<G7`-5Q4AB9+!NMc&GL!0S!5~`oT)i2?cZnVe4b>%Z9HC-W0lp$;tECdWaZg-iMtv
0*_bPg<2laMc_#ZEtNr*Bzq^TH6JCvT*poQ_@EnRSlNod#ssW0}G%Gv_S(4(sv=pJl4#Kc;DDmu?
&|5$Ft;ox_d7(cR^VwoJFTXAe0}AYB{PyAG`!`3YKfXU6d^q{Xac~&4?>jr~^X%EHx6l7J_~H2I#
qoRfs?&u@0!)AV_p<OoyWK`OT>j0`>*Ejb{C6f1?S62+b&|n^rla$%20!fJ!z1WMj5Dhrck%IQaz
BTSp&$0}A?<7ZXa^sCxQVC9TR_WM3N%2!+ogAcKKkh%HHdWQbuy1ffC4{eP_=;8ld@a;SnBx#4v5
L~e4NitW7rt_?Lh^`PZoqfa1PG1;TY%}?sKHQ$tXO&A0|^AX4Ds=3Gcb+1E76h_Ycn%T;n93lx;s
t=O5^iG|1TV>cg`pP*otNSO;DsNzY*tU?0zkPVy-#J5o*#ps`nQ5CW-bl}Ly{;dw9^q**#23_?6x
8Uap;8YKS1r!9O4*noeWH~G~So&$hE&Wj@blnkJg1-t{o6cXIv+u*=#dw7!!KT5;dVnXH3#?vdSm
2F)pc<QubRKkC=IK>lRuiyC=&KFM9Y>^>RdpHWhZTJPp{=-ppz7;$SLZhj&I}N9yC^83tE3mr%Mv
wP)*7g$N!MQzBgdff`tbD!|In&ECr`s&w!fCV^y9;uYUOA8Sx*3Bm-;NV1ufUftfO-Sjq}NY@D%i
t;qJT>S#6+kpEj+{(H%rZtRv!YNmxTvG)2!4Wz>!^i5*Ht#c-RS^JfXS~RO;Aeh|sICAflZ~<4>O
ky$k$pwBjrQPuIVo1#0Q93@pOdXxi-JJd@jp)D!y^O-j@EMq#h}&O&Y9Y|j!PqM7v3MZ3Y`fQl>h
bMX!q=wL0rEe-+~<qoPCC;g!Q62@mywKttT>WSHnO1;jWr(&<WzGAOit(bZ$-YP68YdJ7)0eu*m;
4MznEv&gb=tKdCEx;yK+uGZyoou_!EOM3sIft^1Fhlf>B4=f85p$?OR_$@6H&-jBj97)%g7_9#;3
rpbtf{B!*$F)}rzwig+81U!@#r?rhKX;yCjE)(vDtz)POr1UJRfAh7tk)O^xr;BLYwUGM=*i^z3=
TqJNnbk;UWRXa14}wR+I<vPstEu%@6vOeI7HL*!<@r&gSrTgvEi`xr_^BIzh^9fN*#pU*}mohGj^
m4Px2jd*FcaNP>+wzbV!q%gi2BCXCu0%z)us;6cl!S{g~*<-u+Z?l&#C+_d1QO$x$bKthJzy6r1E
wpU+e`T12oZCV9*(s|6Cs?6xOLATZRmS5JC51|6cnY~sUnVoPCzJ2>G2!Ff&W<S+|>6sP1{6-Zc9
*}$}l1o6-zyix6D`5X6qrR4d_yC5T^-pLF(GvcAB!z(q?w=?Uw_C05{~|PPc3Qy)0Mvv{oUr8gPd
E`1kYR!ZSgR#zMS@U^$HRD%nD9`@CP5jG8zPKxv7Ag2kjGFX1pSDKBinAaTl<|(^j(loldLIfka2
qXO<{r?<-_99%eU`eADw<^O-3;3J(Sgf4<;TM54pvd1w>@Pbhj>HW=2Y<V1PqK1P%%+!|nx6TFo0
w`*fC%7DI+S0a-L2&c~=iQPmx!4qcp&G%ssz1UhXD1Y53#vh+b&R-k-Z4ds&$%BKnxSgaDug&u6%
Tj1MZX_x<GmH%Xy{{-bfS%>2isCvga2^q{ba(w1aGU3>5-dk<n+il)M)qAVWkQ$AGzd#G0=%c3t_
t*j0dv?S3mD4t)!VR7){_`m^CCHzUnXEZGp5Yn6tm|~VKt<D4dY_D%wAV`9qqa9aAR2+lEL8XKWe
kg2IW#Pmn#2d2r51sQT0ay}9<uLXnInf#F&@gwatal>=te>k&slj`^C23<mmuFkePUfVB$+h1zU@
LFBd2%n7P-}&3eCqhgF{|L&vSL4GO-R@s4LK(1cCW_eiKIZykfbK+vd`lEaRWT5-EK+YIxv3oKU2
b{4g|?1&pE3l`_54Z6cr7ydfP03>bC2tWoa=VX0>4T?3pRe?U1q(yHkr98jE&gW)(wPLLIX#XO%D
MABJxk5f5LV$`9+9!l<lIp7Q_DM=|pia~})vJUEWGtvbV#IbP?zoTLSwU(mplJ(R@&bJcMa5^3<g
>}muHh&)8EV7Tthn-#U18ks_yIoxg3)7m(t!nC?7^)Kk32^c})5d6Aa{mKVl@hyuLJU8GX-IQXMH
2u7uhIbvd9hX4pQSFRDODZxM4>02%Un3`{QJ2?2Ceij<^gaRmJmuB23SC2OK}^m7*;A9g<;LSL?%
_@d78xcA%4`QVfuA(-_#&zS;PgdAR<;go5jn}sN$|Ks<P|W3edJPLmRCG)k2-xr~8((6GiLM*BFI
wFUm$6fuZz`tW)$%df2bd#|1P-jjo;-p**zX@L2rwq%ypaP_zdS{BpolB)nW)T_rP{{2UV-N(K5r
4Cbi&MQRkLKxmR|K3g)sqrTAU;SSH_YH>Nv<54M(5zauHxa8CvKT5eLXZ;<R9e8!V^~>q^@6Wev6
%1|_EEWY%0$V-5_J}KPP_@rMP4wliP}>f~3*9rb+3rpNNT~bz7wRibsM*(Q`*ime*w?7Wxq1^91C
r_S?nZTp;S27M)A@Xy3{XsnGgV^OERl{3s&#qR?HV-Ge$$gTl@_~u7dT+MH*`pM^lTWF4lRwPM@3
A;r>p>Y1KdUK@DubtWG!J;|H3a|`;=ht3`g}vXg|_(Nym>GF+*2#vu(_V@!6#}T&dTtnT)QIdGi@
+`3_;P@ba8*5x!VUMKw@eey#8yftr2XY#O-=6Wr=VG8I+Fq;n9Ot;rEc_-yX3(Ex8H57CaGh3DLW
2@j!#O9o{&krLtr82bsSrkeSBNF|60OmkH{@Jk|7ZNO11`<gSM`<m{eeBw4=!u6hH#^jc-=lMJy%
LNYu|JLYxSx)Gq+JEju6PSw%4U}3Wb5W7?mo<b!tY#>f9k9ueadhe9pK+p54#Fhz4b}I^J1e|{bj
`>*)1Z+*?Jy%oQk`aak&IeVx=Rkt%OgI2PL7X{gZ*8+1Ipsrva=U7pYp|XLz~8Q_L`_i{P8D*cAG
dy7mNxPtBImCEC$^}{Z%e|g-|N}7GAGsOj|>~uX-AE+7T7+yyP+yRB{#t3QQVQ@8wHPCQ29%jS$^
5_U79X3Tf9+%hl}e_+dcHwP1MC&bQL+3Qz*8mfeG@JUmq>i!+TkHW*SfY?pN(!Kk}CtaOm>g}P5b
w|9lH(aQKaUv&?7V}<<3l{I-$-eyT4#ThmGL9a(*k|LMkeUjw`2r={F4Wc}nSm538atv$=$~n{Y9
tNfbB&yr)2jl!M*yBY(q@ep+u`>!`7Q4ZVpHDjtvI)SCyHO*!Nw05!f~Y!z1$+n~mZD^O7#uXytl
8Ov@!Z8zg3U4&kaSl03I5#y?TN@h1+7&UojoxexbGZw+l^q+>#~&2A8*Jog+Iq**z7S|LD3a9KIB
GV46}HW&?8}~@p~XF92UG9$JYg6EKWl*na-C%G0x|a)6fB(KpvUxYJw=w(|^{!5S+GV!+Z_9LWU;
8;TBfNUMPAgq}UM@9MCPmKt@M@VBj>CMle_<$l35Z>Vk_04%;%%$05(jUx~+1r(8gspK+ukhsU)D
tyFK=Ziw|M*+@p$w@*xwf9Q<VT9X6VFB(c@Z?)ggw-_0L>%<9fzzR?s_+94le2d${M{3oe8chvV<
4Lklj`J<uB$hGe^n8m3hfnDPJ)z~KNAwAwkx2tQ!M}f$J9{v@zTDm04R6&3Mz$%uC8F4|iQ=_>vm
061gPi)URaEha;f$^uqu^fwe1w`^K-cgZA9m^CH9p+IhnHo^OD<{9AJ#++M)&iOg?kGp;Uv7D@AA
$)Je`&7s#t6SMF_%Y&tW)llps;SZ_v~{NBu|$aPAOeg9R`y2LVaD4K&LH!IzEW=D@X$tn)@plCs5
Qx<oxoHns2#J6WaY*|ddwvj{^J%R8$3FnamUy0`{S2o$FNC<G%W5FX+dVF^v9Vl-b)lS8LC%55+k
7W;|-;5T4#fyPK-6I$#>XZ=Rd?>9Ra#&ZF}%*i28K7@yJ%x8_*Ib6c5U82%6<ZZN#%lGI}umh_p#
6mwZnc;F8p!T;|{PK?fdd7{mWw;Ho1Qn-FSt1~e2_--*Ss5=tgTn=>ZU+B{XT&$@4iNCB24XaR5t
W*a%Oxr?W^s0%K#xu4oZj9WZ|^EP_Ny!6Gw=!l#;^^=BYO~9<1_xq>vKlh3DQhZv5Sh<30K0SZ;I
jgi95`HhX4+!I1EXB>0CtBDq^<eFzoUhDs}q@2%{9EJTT(%^ad&A8Ml8?ErG&mJ9r8&J-seL0C##
8hWoG}Db7)h+)9ccI)p>}G~H=A+kn3Nk*7Jt(G42ft!rr4)6i~o0fo+Bgx%d;Pn*LWr3##~gMMev
DNxfPHF0l%<*Hqp_NunpusrtrVO!Q83gP-AIaOZ)1CYiZIBPiU7*)D<m7c#!I=ZjJ8mzUm25Y7;j
Z<t@9X`W06xUxmZt-}W%*oQ~?CjgAEI}iH&mI2k-yulshlqAVAKD2}B~zV+C}K|AXCHB$rycl9xX
>e9_*mjXj}ZZzjW&R)AQJR1fm(w*wGEYxbic0aFwgSimPW8sgC_1oo(@u>`!$7#z{9#ukv#5T@9+
JEK$b`l>7|orAz~mf3AAcigzQM~!e5m%W4O`85*v40O;^m8&gcVdp$0#K-J?Er;S+&8)AD23)BV`
LsObnQpD*=5fy21G*P}+&GXZzS@w2{Sar$(~Uif$-*??ch89gF~2w0)_-#<H2lF1CDtoUjUavFSM
{|Y?2iQUm68QNg9E<x~`Ei$w$$LlKK7v7PVMMGUEDKT&w1B)<>GhBm3k+AVDvRVvG%$xac^E-J9%
}$aznoO{?R}ja`OGIh`{NxdJT#3bDuWasX1ICT#m${s871(dJkW*#0rg1tetlJa1NpcDR{qA=!L>
qP1!7px!j#;8@m#`!hD*o@{+csdr_@=DFg&FqL$j?w$4X%r7MgIGy+Ufq!@np<HsvD=TW6F@TLu!
J5eN2*{6~ofVg#BM0Y*QW#XKZsGte(qS&7GBP)$m}<e<3f$tXD1P#ax#v*t^)6-%^~`zlG77;(CN
I&y9#cs4ss4t2JLt$4R(3zZL1mqfKFN%yrem-i+;Xnp??xea<k#lKG0hg!v)`S;=a6slhUMdRWzZ
t*}ARL@`IAh|pQH_2sM|BDKK;)$(um*i~w51>=U-CTX@v{*U4^!!PGDqZ;Z;_ZqlH+W{SGJN4XXJ
nzSN*5lp2oXymBw9?Q4c~5l}z~l%IM304(c?lp6(y?JvrHx>^Xux1!4>Z_PVY54cFIWF(&<)o9lh
VId&%XdpN-6kl{#xDFJDPpg>Z8k~PxCEWd}!8G<Eu+@;&#ZBn7wCXQs@&%53B32U%g(Hdo52ez5-
xgvgQInz5FuuKZ_uLmhzvWY1Myv6=;P&o;bMAm`Ri`(na}JYWm>;j-32(GsY7}k!aOqG4iP?fr;(
)kaj4jwiyZ+#ud;7R>3Z>3pTtRa4!`q8h-b>pmLvpR|wQed}egHQWLlXz9?|zORi9nFbS#H3s(e9
g-jrUM8;JENN;dls%ykh{x*U|Be-n@!!f+J?RXi_-+(-jpi?~wd%=5}I@m)%B(7nnMPj<&L8}0o;
^0nMIpM}aicH%~lM!wSrD6U^;TsAx)JHI;dH&rD4&*eu=5P#1n!W*G%jA-zV)!82KSK}h1t20e$e
sv55*T_j9*vX%C|x-TOaz(E$m<V1^QUQIkSB(gW9SHMd3ci~9}EBPr~3&-WoPQ+nZ6dfQ2U{L!&g
BUs}NKG-^4{cpU=v*I^P;7EQ*ZgTGt6)J{#{~)}1r3Y+n~6$+o=Osr0a6RFaKiJyTodqEUa;dX8S
Htv1z#M&He$5S|-zE!**ek=`L7zL5*Hhuwq>2cL6v{c@&dd^ANx4C>p?7wAuVhZpp$$Y`^QAD`ma
1qNVfQ&0xF*}scS4st2=Z))q`I`waKeTOBk@5+Lj4IX0Kn>2k(%|Q7ZeVfW#8#audoU>&kxGyIr2
1<Ld0fh}`7z<-}w*_romme?HN7u%ItX4d{%&7{ba2d~GHx~Ue!bGV2kaXw;Hef)eLBcNBrYbNd?e
lKxg@)6GHV15Jk5PGfz3Qd;1RZ=7J>Yx7pfqiA3#xz`>&n46e8p%o*v{13FU2O-mss5)(_4FGmsS
;=TT90}$JG^N_BJnBU>F;KUCs>JAQ_YM6m@YWxh$U^tTr%25RX(VTuC@-60Hn7L%~bK))2+8fuRR
0yJPvu+>n)AI`S?L%cj6URF+Vj3{7u8HPI`UTQt2eqBVsUx0^w!-4gXEV;lO_AYgUv>jBo4_4oou
rW;=A^N|<x1zP(6(}dw}mT>;h5_VE&mKN3T1v%0vs)N2KndNgx3#`@d<oc)d=0b{~uY?PM8F2^SC
!=(p&upK=Vgf7-6r%7)1#9FD0stLlgp0E!hlV1r5@-;nXgpp9zb&$lEz3gE!4D8Hc6WQUEi9BUo@
*?CXX{NVV>TrtXVA(n(Tbh>X)>IXIy>xjQTRpEINcDrA(3SCQvO*(FtP40hZ@*=M=r)Hs`qddjPi
ul1QY7>Lyou;>b_B+j@8V_!yq&|)6i4Z(4C4bWP1(bDY}ut@(e+;g#!$&#?W+x?Z;@BCwSw74g`Q
N+WL*`yg?9#qNW4Z1CA-CkD8SHWc!3`>LKA=gC70(Q$W#1$PkV>VluvKSzf)^MvnoLLE}y<cxQAB
<UYY@azh*D<9t!_pe3Y<4Avxv9+GHKHdjS8#hIxkEX>`FR=x*p5g><wPb-S}P}cA4g&u_tEULsVS
y_yX7+3X0=#fM^*xT{JP*bLKkRY3WOwlt5;|R@llq2|((!(j@iSee7Bie|AKHuVTVIBU2fN&7_1p
ofAnKrf@Qm1=B1o;Z_fdf{3?htP&`oZcEB76DSL!?T^0P(v!z`Dc22vm~~<MEm^5p@wpF(6PTVcn
ESapg%`5OK1Ir{PrZ28#$ySJ#Z<i(x6-D>y6~L9eTwcIiUe2)Uy)Ox{{XL5}~nzMRm9`hqq);Zlp
mt^4FRjC0{Wl-P65Q*L_=0Wz1TLV-~9k@*&PT?c7+mi_Ngs^pIO-;<vgPNV<zgWx63T<KLxIt})f
;*qt2*BlaX#8J6W-?4kpQvorphyx6<x6^Ix>~u8?!%7v_nv-T1$^Q5*UKS{tarip4AGnz%iqyLx#
dw-4G3TVr1o+s}?9dg)QN$KdKXg4ymcX;e<G2EGmQ2Sft8yuD=lk!U1tDw?)Ms^jc%9bX1+M)dY6
T}8maO2=i5Qr#GUR+X952wU;gJfJ2NY-mOa^x8w<OMrZ-P-g`-ti-&Dj+gzl-^@G|Q4o7Yp)!=Ma
-Q{L04?`cFYZJv*#M6WBEsiZYg<M{^e#THXWeiB85iJ3o_A{v;jFa@5MGAch6bZzdr?<I7y&W-!k
!=Sq{&UQt-V6~Qr==p~h1<JlvMvGH9Z0mq<aBVcOMj6z~Kkqg;`mm&^upqjq&j`jgWUIkHamO#m5
HU$<Pcps=R7oFXN;$?L99wC>y8x;RsB*`aJcW1-9yMgr~)gdF)B51cdomQ*e>h9q5CbX}Dt9V#mm
dr5NtM<FL7=pFD!0p-+IPLnP(RR#P;B|@h<Ti3w4XC23jgXwTL`T*8X$@7uJ!nSnq*Ggm@TBOVND
pupoH<|utb5Ov;%&vSH^g-Oz<to!bDwl~)Dw4n(vPx@@Xl%^Dz!-R>Y(~+HIE?m%3f7r8vWC%s%X
7%Y48Hbdavgf%wp)YW{YUw2EDah1Iv{wm<Ddb2x8$qk2`yI6+#Xm4sLBlOI$Kx48$~2SU*vsI4OB
T=Q>0yNRW5aUn;jIihN@!+60vnuyL5<t-jKnDKWt6OQjfNKbGN7l>&mhbe$yI$t@xT8jHxsN)efT
EFvF`B7f+~dk`Fvh2We*F~PZmF_9XMiVK~;QkEk_6>ze=EhW)aL33|_)s<SRZb68(_@>Zga*|B)n
F>uL4_7F_td5zd3A(3k#*W)%Y+aDJSaNTz9<Huu&xT!AeC4zkk~kn$kiXY+shFA$h1M$__##U`g7
IGi9R{{v8<#?<I1@9ngFHEFUz};lNiKTyH_Nzy%l~O!rxeLM9s<r5rCuKu9s@z;kgl517}ZwrQ>0
wtXwdZ(Z3VcV=*`khM`UNdmA&6bNim$IQx3RHk=iX)Kb`J}L0+`5!PY39VFRK19$yyt*XWXA;W)&
Q)1!D!5j1oa-1s4aMTt_vg|UXNMKP7PqS~{^0<o@3gTYk_$G{+pY8!IGa4HDNeOk<mP<P+u+bC8$
MmsBuU=t*HCm9DOI|OPuziJ-fMIvxpS3bL+Q9gvJ#lE!A+c~_takc>W7H=5yq1;dMBQh<>hmji}m
9ON<UG)qdY0=g00%#zcB8rbSu11mp%Z!2RLk5VK+~wi;VOh+R$?<(k?znkSoxA{vN+47X7ymmnp@
s*;0fouNp!5{`SoHgh$2iIXp$ehoW{9kbE;)NQIH))_`(Gd4zOh@po27H-s_OsZ@BcaY%XI26`2C
NnIHfU{0eE^twa*;fN2(pFXL7%R7x3y49aviz{*6Qs{}cOy04Ng`g^3NNd&Z%tB}AhJ+!ta9L?z5
<Qy6*+`G<@qEz@OGMOdgiI5)}SBvW55&MX69&saHu#KW0tSB<U}plJ)`0YPoZ!-9izXX4h2|1+{v
$Fv}3?r5?K#+A!Ti=+}kjoAPMz4T$@)lI8Nl8<2}SeC3Jyk~}+V?}8DzkINm&XB_lr;T7S9blMOn
-0CB<RzG3f_b7}nv1FBI&#T*C5jsn+2h6hCP#hJ&rq@f<>TQjFF-W-M{@+c$W7l&P=V<#2!hzlNO
}rUPMA3=?DP~t7|$kjJ=CBp3(CL1_w|^!LYebX@`_gQj1yOg)Za`COn)Fohm;`$6*b5!p!JZ)JO>
(IHYiGE=^iYTh1UY-TlaQ!BC%OOQwOLP`Rjc0*1-zUnr*rnN(YRUBPu`0FMkUeF@yori+D(#YG^6
s5Y^T8%KkmRP2d~>?*8qw|0*M`7Mk}rwK0t{O-aMhz$-*R8_{2Xy`BI1E2^LFB%cKuPO@&ap*Bpx
hJ4Jh=6F8@m{ke`GF7}=Ib@!wv*{Tp6d~piFOc$SlY*G%fWnw2CjFQMFM2Ns4PZ=AMlRL!`8=OcS
!(qbYhR5yV4hY`>OrF(ZNaf4Xm12}@iLg<MXU!m(7)W2Rw%3oPmi&@R7x@NASlkq<MdLI3RPaY{c
xztj^QOk*NbW9Vbnz@c*w8LEIIe0w*6eJ8Xk_Q16(JnExsrc=<%95*intBy0d4dNPXd)SmnMl2$6
<S5+o;Xz1_Ln;9+a;s{F;&R{^mCe9|#Y-I9ZtWO*`xGqsl-me{ii>aHw7QkgI4ww!Gv3&w2|BFAG
SnqHuNay*u+)B?Te7&7V8;DN#iI;>3f;o^3n*n_q`@mk2ShG*y_WRTU+hg?%C@HJY*1WI3+i6Ye~
m#R{}8&RW|RwZ?nMqTlE>NtK17Q^FVchKAvO|OZGQEgIqHQj+HWFSi=Bv8JvL2W9>(D`{Am3Hk`#
ZSXUwz-RF3o@|_n!&AEl|6mb4$zty=L*U2i)uHhuTT%;RCXId&t+I25Rtu|yHvF#rY05BBvfTlO7
2~7T%?KA@h0dr5wAxL{w7KgNwvh}2j4qt+?b5}hBQ(NCkx#_OD`JMSB&>seblXbAl0z6&I(}qlSd
Cn=5JmI=nVG<y97TQx&nE?^N)sl=>X%AaF{m_jf<-68*^@Vn~D~|tkLlf-8siBOw2t}N74I8o>rI
vAki)}Fo~xFBqE;E|EMH0h)`m61cilD^3plFLKJiW^eNB(Uw>6iF$Z9xB1&+44F<e49QFBKraVUA
WG%UcdHx-le2XHGgjRCH!FzX79L7^%7slfPx&XD6QMHP*W~daISy+EquQ^;D+{lu<$}#9WcIyw)z
r{#n=wJ1NrEPaBB42x;$~zxcRxG}-#SxOVwWZSWcrgK1Wy>;B+St}dnH#k#=H(TS&Hvp_xw4;D9S
ts8d%zK=$eX6W^3cIjfB>3X<T|FZcbs08xL@nJ<_D{^$q(DzQEN2fM&x1r!s`M4r|8_*DU~(eVSH
V!Qs##PdZ>dw+L09`OK9NcXS31{?nix-zzuKmyr4qr8eNgeSMicW)`_;c$i!QX1OJMUB=)4N1Q+o
{0*a3o<VaxfguSlgBDt7ck|}kyA7!oXju>5NbSCo*V~fJ+LAgpPoWxwB<Y9n1NiOQWCwDVQg<4OE
mOjuWCfIm!qrQogrfG457f$!VW7R`si}8r!e)XlRXwd;8DRbK_$<Nqmf@~dD^i9Z-vVS?^B#43_v
t*iJ0y@cDN^Pxxg;^$x?_g@KF%wEcp${p~D|d2~qM<E5mabZwlkNfElugGV1LM3V3PCAiyhQH6zI
J!YJGH)e9Km9c!iC|XZ(+kcG}Xj5GzOWAOPU%3Wl15^OtYfiHBkpeeG+uKt6VnpWwqZc5UGQ}Lce
HA<D?_Dvyt#l`|;kY7D(lEsGywfs94fCLic#r_dd#j+X77I$sqycD{4&m*Vmtb3LR9#!*Vs8h@Jk
*aPQO~ZGpgE=3M!#-^0*K@&!ICU!&4>znqpfw8T^M<Pa0=aryvYKB3nU`c!v!D0Vtu^*?rkXgCw#
HNs&@Nalf{sVR8ex4**Y#~0pk1GY0g%US($WTmSl^?)y~$<P^1z6-vmrVkDKdRxF74u}(A_rfx-<
*XnDh)Pb{I+|TCFqZT?dJ`IVdxs@K&vfQz%mAdx6zh0NtE*2qZlM*AMuS*D10r*_VMOLx^3O#&6F
W%sryNhAAx{?KwGgRw1Q`#dyF8~l8L01{v={69A|TwY>sFaPC}f(3{PHB3T_;Kb5v}bHCPv=UBci
jK8F8F5BsFUxET)t>jIKJ8t9UV<E5#%nPAD)PhVuP<Ysr5;t-3tY!)1duJ|XWp8TVou;Fd^54}HI
Wd>ohGns6fD1E5@qG4gRL$)HVHLsgbG0B}JxiJGE6*jQ0osVJq0djW{0DASz^m55p&Mra@&w5-V0
o^PoY)p~^KETxe=9I0C-*yfCuz{8O~0b3|DfP(Ne@Ov21g$mw>VB@ACz&J-6Q}c30_t(ChG0clqx
9~PZeCf?Q5u#lH*Rn~I+~tRM#sn;7(O+s@va(b!$W%n_O3DO%<dE>-t8R8&g<g8t>;c=|?Cuo|@e
oEsFb~zR4p9uOL)M3Z4)JXyDJDTdJwM-ii)S{Xysy*dxf@yLPGX-6i+IUWY&kHp=s*=0NG?75^de
sss_C@{bFcQyyygI21Q1#6s?jy@I7L-8IcUg_u>#&cSi-pJ#aSi|(R1NhJnqF>y^O`ZVTYX>rLK;
H&G;e;=}n~0Jo@U{0fD$hlS*k)&SqFdv^7-s8u&$Duv9S$FbVs}(*~%*mTA=g5-rs30IF?FPkB+K
UN+1TG`LPx)2@baH_PWl3srTI$5Kq_g{UwXupm7c;JG{)=xZ%Lrq45|y9MIp3~1~C*-aoGOE}lJ9
{lCeqL@9pOtVKxb{kA7-ds<m9Y5w8N*4P0GQSUcdu?@W6Cl2kjM0ZJ9_QDKM1_WK;%iboF~|L!lF
uXRQG5V_-Q+X+1j;sVyKRbrH_u^v-cX7zkZVbeb(gEW)iD1H5+Bn!Crej`)p*`0HP&T9ZOm^lDHC
xXDCMzqGFxP=KxKPJT0Mq2I?s+iJU=<XQq#o@FEaav+Lg3tWn6(m#WM#KfCA}+#`jCU2u8Vt2N;j
h3Y<-n6^l<tqG9WfGSwAJ98G=qpc_5Us8viEo{(L9vpLK2xf*S%;<d2EqQVCjDIY*hS_Nfhj%ruv
<C{Eqk>6#MtOhN)gBMBh5riE6oDb<xE?U7mu}SAn>$#LBNJX>AC@(n98`^aOpE#t%AmnYveNsXy3
(b7aw&ulc5E|n3n1u1Z9Af9$lj}t~dfK|gfGsH+)ITD163&c*hcAOift<<)l7SRiq~x8fAD(CNxX
3a7%*R4fcqRAfm5`zr26G|k7FVe0MFy=%;u#w1=aYmN5T}nKV#Mbeg<ix$AJZv_mc=k9)d9c(_H)
dEF^)3sf%FjP<X6;G{95uZt>76^^qyKsA}cH>66K}Y5gV0^Rla-#6qpmONr6c8Ub5JthJkj<8I|<
C%-ND8s3c^>7CEqJ8?=HCX6mxE&}t4ZYhXCsmq|XjpFP)=dd*>i?J#C9(Y>T-lp68AL88ecQaPb3
i&}MyS6+&rXX2X4iF4)pT3n7Oa)`2!m%H0kQhS>6IA{E%75%Y@uazc`X=LD1(<<xn08kJhl5UCiV
MA4d7FNT0!h5Kh&zgwFPtiXfaRB#$Y_^s41({#;&*2}ctL!J}5{<)p%hr}MFpxE1<G(n0ua7Opqn
yvLAQb7Lui8sSk*<09n|(YNsun4*h!t0-FYLo7(9+XKPjIWFe4~J5<7II2;$O(3k@+l77Ck0gc-;
OeQqGw$=pt63zD9RtoK9eOzbSL%Xf4hgrf8~QmN$vSXd^OCL6>7lIDD?k@x<wA5%NH1i;y}a%nc>
d;CTv2Wbt(oWw+)ioe9)(zuIS9aGe{IUOm%j)BK%G4P^;=UiDGTmSCg{%o3$(!F`4E&=*0KqUJPY
gExZfB*)ykOA{b1)D$M)bWWP$VNOCj6KY)u2_*<vXaI(9@L2_zjW2Z0v#1LrLf)5B@-9GjX%ijhV
~nw=0YsDc0M0*p=A&<xI_gxJ9rXmxQL-8d-m{9Jkf6FjuXV893f>^SOJ}1dRGcqKaD%N*yIv<xl>
`M!xuGB2#Kp}xz0}{y7*c)73;l6cRw-^4^K@K(CG}kSby-&WM3B$3lQ%Dpf2Q<X?m>#3J2^dmJvj
dP^!Uw(lecd^ppoJE7M_q|^CsGi2zB>I<rzVNoKoVk(A^HO&(Ngf`en@Q$#i@d+}*#!D7>`m5SE%
Jyq^C4$CDSlguq5n`X!D&JVzc^Uy74(D=~{N0gY!1*fVI%^Zf0b)1#9&$L|NPkG?;7PT^!#y154C
AAtgae0+8C)3JPfck=!N4eZ0;PTmb*BjMnGN0Dii3>1?{lQ0-emqYXdL%x`1<vN}7r&|yll%ujHY
E@0o`PTpQ{`mPX&tDz4o}Ikm;w+~HKjmW#H*u121SHIOy7k9-_WJ1O!HeT}r$0cadY08O?)^|PAp
;-+o_paFK{#TKsYVNfTr2KY0x~cKLMG8*(U>xPiRE!=<|`^>Ws>VyR+)V_Ek1Q|C6Ji~t1vNWt=E
!StqJ<i!6QRILcAB|z|>HzFwvAWxN1*5zll~ECtH0`*Jt+3I|j~l2rQ)<kbYn;&~(IU$?pwg<U29
i@B{{BO>J!%aV=p)IiAgM&ldR9=i0COI?bnHJE}{rYTMab6TpfGRE~^EsK5=(qrmj=4~umHHkAC#
(+j=S3h7GAS-Iz&K9J`r)BDOv2-JO%86pZseB`q!4$RJ>oi!SVF}4&76dQ}+IWa}2d5#hJ2+v3!P
^Wb3PrCo4J5Vh$l%eP8d><f}QG||lC|@N>RCpXuqbk>xvExNn6plr0KNLy~YC!D-y!k-P9^Q>Y<>
dDu_?RSYbII1681*A0%KqO74w?p*kB-~X47jS%LL9scxwq$QyZlOli}5(do40t3oXwIrB0QbtOn@
4=6Lbg{(sz_5s&l-)o8P61+bxnLb5y1@QWThQROYP`KCe;(d>mD@ajH~Wz-n`uzUzwZ2E;{0Pqqx
X9cYNoQt40&n3vhSz=;d_#WuE4BvbY_<7Z@1mt^ak!cyAztQ>&KNS7p8c`cI`1AWMcRfiS|)ObY<
8q3&p)-U-Kxw}D@jg=%<Wyk`uCpRQl=UP%tUIDm(77N_!S?9vE@ORjh>b)X%Ol*!Unpw4M(6;wCf
OBKlyh6b7J2to9p&mF~hDu*ZRP^l!qM+4YQ3OqEa+&cAneT6~;=yo<U}g<z558D6Ohw=UhpaWTjw
96!X?r8<j(}S(`-Y;X^sXQ*DSSDOMP30SDoP`!1|(aeex+ausTDj!LMw*Zl+_&N7i;O66mPa0zha
-^ZRCJ_7V5Th3-A@rfKYZ=i&XgPo2>>PE@nuM8bF27wu0u6%r}eHT|EBi?GhF}>!bTlLFZjKB2c8
J!FOv;K9vi@qzS-*5)Q-sjg%vc=3<@mSq)vfzH+c=N2;f*8eE<rJv|IGZ|d`;(xW}A8i$tnuP4&l
0QN-!3SBC61s9JtX>XCG|6C*vVkyp#pxTH<uVfOru4|)A4|N=cl1q~<$nXEG10K(K4mUzBTShocz
G&nfXz$H*MDB%nl3wTN;*A!-Bl=4_pE(&<{L^MEFU6>;2{;hX$o+YUQb|^n7EvUmv5k&2v&1OgDE
l`g#+~;6(a*?FD|k+@L<Nsxxme00#BYkqc~L5;Rhnj{+(6+Cj;q-%2KfAlgxBa!iY7cmX^QN26o6
lu55!AXjA{0((r@<Af-5V?eQEnDAulG}Qk_R#dc(ml@bcXVeqmBDM`ExjE)jAStX2H(OMgJmspPk
}gJ*cMpeGPU!--Kz?mxT`%hBo%(b#*kp?(7UfQ1wlP}X^T_|n&T#p+R;4ncjNy-a<;e?*)HE|7ze
e8oO5DAqoI>gZ2h{mG5*@0W(k^;fCWs68u&g+2^mH3x{FDlwmQs^dyEa<Efu4EJnbJ!V<#GaNhlY
&yG=+qbUUg^ozg@<_(3j6qpFM395jF>XBd>_}MSTRxap>@({y=Gcd*WN*>O5b*JTg=g*N<G6Ws)O
>mI`@tVk6Y)`X!s<E&EoN)pS-zNtoro4d{HOpj`Dd{0mtnU#PKNW4PXrIMA(1R|t;Z!QR%)>Ocr)
J!>ZqOw)YdS|ooMJIO0EJABd0$KjX5Z5g;!M%@Yp1!h}14E;*423Q!Ci0UD}3@P=|9Zz%Go-;Z@2
9F0N>gn}<oa9ac9aak#>s7-x;N-y)tajC=-XsbL$ZTc|d$CJ2vr7;4(lh?q5!maR#3*SKadG9Uns
Vk5GQYIUltWjznAy2Cv5M*L>O&|-R!#x?wQrja4I7=ll2^r)ZG75!gBa@fx9GEsb*Z*v~u9&FNC6
AvX0G8*in-b7Fq4!H3+xCSZ|EQ&gTuXevl=gzk}#2z+m`y*BTI+>$=jjI2ZJ4Ck$Z7H(^gAY@tSk
=uDIrg%PN!YQlu!?@(6hNCIpuK>)zsyKeKiM?%Ph&?l3&;Tf&g)E<=rBsTMOX2LDJo%R+IMigI@8
x@fwpz$*_*eggQK60PLJNx<piIytdlFR8MJ0c9tCXe5umvTFqYYz@88D>nnk1eYn+jCq{SC6bZe2
7b|-S{0CEnatKHL)vTY!13BGs#aQgBC%`Mtp(9OkZIv<mHwjhX#+@sAZn7fn<54O~RW14F9gH{W=
Mkg6e0Rp!!E!N#sVEGp(AKtw>`i1P!&`|4sr_&*2S*ObpM>)b%`~IM<80sHSUp6~?&yJa$r>+RF)
05Lz$0exF-s28y-h9=i&JV{&FOG51TnO7#t0X4C!*=#A6H4doP>?r2zG`ClMRLg<=@uk3WXw)r&e
1(8&C+15$Lx-<9dyJ)lrm3~8Zo{*gI9fi-MzqAYM6!o{J!1hU#8DKl{yT%*0w?rSpTBMre7g5<d}
^};_jB*c#BzSLzN;}Hkji?`;=&E5p?tk#L40&zayk#%qcUdAaN)+mnv^f&e!R@C?MjYrSmctI@(O
tWu+@Yh-dws3$2{ch`ur-Qa&pqcLiYu+Z!&%Ip;WH0k%x$^a6-+(it!<42)PID0P=B^sRaqRZ)oQ
_G>R(=DfKo<5RdXDCSqi01pIUZY4`ByNgtDL{|D6zNEuUu((hl+~$kx8#29NuS`;{DW{V|WoM?e=
wv^EH_hUn6m~^{i?@OF1gH+M>+}?<&LgBZQENqFE1)^;_NtX+ny3>3_<Ts78d;^<_q`p%i9}*2ge
H`2jslN?82_6-aZ%(~h;sGzAM38t!|mW8cv|-Q%Y9vbDEldZdu3NysH&ucq%2iZdbh9o<I4^y?5D
6%GwnSCw77nX)!45D%Ln;YNLTOXF!8?LSave(yG*VynStb1+i!C&STW6tIY)u+4w;9U@JP)=H~j3
LMixm$4)c~wIq<OZ@|ugo+H~2f=I>=6a_(^X;n5=)^U)Eexsm+<pJ*1^YQVB<ti-fYt&>nSy9O#y
gF|D^c=g0F#*9^cv&cTGWMfpV&y}~OM^$$ss=|8%3;1spY-d<C95{WbwiaR1v862Xj160q>JiTz?
4Q0ZQY=Z=LuIsA6qf6=KLMVckvuXZ8c<R<6_KHR-!)yQ$WnMrcW5g4TbZ@az-C=e*kJmMINd$i<X
)_VU7_5nykG8lpp8fEKI`%HRd0-gJuZf6>K^I_)~uyr1e%GME%qyfbBKeU+LwK()2+)HD|1Qh=aT
2+DU;rI6~jD&DErq{wu(Y2+O-;^LYvAGP9Y+@0&i^ZAhj(Jm>bm`+uxQ=q_SI9whtjYN6gZpHOYa
kj~%+Or5)ZG!WS9*Rtif(a!6=hCzL0tX-&%(ubPi)kSKr@(c;F26rv!tc~H8Lq;w^}n<2>95UzT=
X6)a)Sm<e>Vvv<KR_vB@+Z7#$&C`?>rEx!H;c1j2XI$yxqE;nRxpi@Zs<nXk<*O#YHCVK&7e@FqF
AGE*5Eb?0_ENDD`Re$JP02_I)9Ynr7F3oDEN2Zt5X>BV1t0H%FbFR{pGO6}AYt~<VO)j%!WHf`g0
7`~6N0{i_p5As_x{(v#~Gy$t2@B9Gf-yaDx?6XGR3Df0oZ5TV(ypI@88>~=&rIcx^hPJM@;frmQw
ZPt%(V<%K@p%<}w{bPkc5kxHrkfu+$A)Cf8|}Q55{S&{{-WjUaY_J7O~Ml9mj53#?N*oJ(w9(qb6
-fIgy|Wmf3S1!d;j!tm=Zd(;%m3}M%&@rWD_nq&gOLCzNQR`B-}Q%KEqh!l{mP`#aq^|(00775*x
<=R<<Qya|kkBK;md9I{Hl=Cnyy|$esl?A0IL6?#{X@QMpWk!XS9DZC3C@wR4K%nr50Jy%$=oHe3R
6FW$(~{xt1z!l9Z(XL>dY_KOUk-mO(SeG0@r>k8y$g$N4m;>gEj97u0pH-^#}W)aUnu~n0Moj`Jq
j&lkCA%Zv6@%)*7NC9GNd@go}TavSR~yMOnrr-PG~(*5N+{_VXH~tMC*F+wwPg5Ts0pe10MzodAN
yQyJl9pdy%Q6F|)6+rbY|ZX3w7-dc`w~`F4eJqrS<5j~EFZMvEYw^<`!*8jO;W8>OPAo>c3X6RRi
H14?n+t3a6``Zeq20X@&>l)p#C2B4<O*J^GK&B>|WZ_pHp?Vo^B-w5F9APDJIxrW>yzijQPTK12z
h^j}n0?x)6eK|4W0B<8`OkpCBE6-h`*0@PJV-Fj6q+{!l<v`57OX$`_N)#g$tT2U=wwMo3KzfQ{<
ybKJ87m~HzyD!Qi}2zV{>Y%mIu1my$3|22$_Oml0CFJi!JG`;e^!@P8D3UQ&D&J?kt*lR=i|FK-&
YuCD_RcuX_#{ptK{Y_G%O2Q|9bEk0G*%D(CFa&z7wm^K#ETxOUPzt6=`B@u>hYOzj;Bvt@9ET6<Y
^O9w-5Y^~DDl4yRfS<IFQT&vi&`@!FrqcrfcA6s7WxLZ$JIyTOo@syj+Gd6`h`;gsE947WObd4;}
wa0bww8^+_6WI{64rI(=Lgi*kuOYTmL#-!*0HY8SV8+Y-t75sphMjRVz2^pNjWs$|ycVcNnNhs0A
w=kF|;+lwQ@dci#A_6lPk!=NNDfVN^f70xzgf#H`NwBwLU1%>@Z{KkVNtLIJ9gE#0bA>4K7&P&~*
q(L$N4S`=(xdlR9KMGN$?chvGRb7J!SVxhl9)ltmTWNabveJ)eB(8iqGz@Uc7~B0f>7P0Ms6qvgE
TpYqL#>LY!14f=PQoV+@iD(@yg&B-4AO>_H|{QJ|yv(@5H#;kqVWi48Mou{4FsF5d?bcijNrI-7(
irtU5gZs3ujJYVm}t#@GX<FBojNzm#{W4Gx%PI9V^IK~vDw@MdECmm;N9pidIReF^VhZpk5%jb;2
f<n2&$vVJNMIZsP@0*#r;UY`}fObCFL2BH|NSg?qJp;85uM;+OJHk3s^3XSNsBE=gd_PX7Wm(l7B
FQrvZ)nbEN^CU&7UPSptWGe!#wB%OOq}(y)<Hkk9x0!2>Yp6^n4rTrV@<n$H7>u`10^{PX?>F$MF
*{o|EA`bd%p>m%#!n}r7@Cgt1JXCXeEGchc)#0fwb(nRm{+66J&;`sHL1?k)v$?`nox^20=jKem<
5)Afvy(S+-l?&=P{e%RRE@^C3;#6|HFzYyoR;#wPLo+EEND2ZI3cmS_x~T^rFs|@&b%DUJ!LPY2P
82DDp-3k=P4G0VV#6Aw(E_QNvZ$#aGFI2Nx0~m#6+aoQe5e(Zqs^8WCZcfGDCIsF+?`_tltNf~*a
T#br4A=IqJS{`uA;^rHIL|M-?J>6^$QUR`{nY~grfVEY(hD;+S%V;0*y>10NM@74W0JSwAssmX!&
XZ-`jD5sFlt$?kL27s#}#e9^g0M*lNw#dFw?%b>o9vO!L2L&(BKP_Hxpg&Vt^;U{D%#(*WuMr!q=
u-*}W%zm1;W){-prO<-M&!wF3bD!lAmPi|)Jc17Q49w>9H$F)qye*;4C6(SR3iGSU>Q6jIMm4Ai=
ukeL?2YMhuocqGuJvXeXN=ICzWykOO)1>uS^`IP;3z|MSUY6P+li<m*lTINTE8Wv5|wVVsxg8F>s
1I>w~bWTh_T^nakmMD1bdtmpt}nPE%#N0rVknP4e5swlpIYCo{8#JuBR*GC{K;Lc!TYwPuF1twid
!+Qp`1Fq;{e=owO*mns|lC=k>^>De2uU`JV{9A|1zPSYW$h>MpfHzCTSsWkG2RgP4PKNDijDbNG_
Q_%}r!7JiQ8AGh#LirUsU&ommuSBP~(&VARJ2BQ_Xe9c99YRN4FM0M^Ek9WGS~>H&Eu3%hfVLd-T
MWTaiRiZif>bcX1q$6UxPlQEp#*iQQc)E<0?jBV@ocF*)^*;&GBkzdiJ@~r(<g68aP|YD*Z#Z~%K
C(&wjiu>v}cq!B%B~mc!n{yE*Khxf1<Ww$LwG%P%anWuPo<e5a8H{WpGn|d*OuKG<=X*7{s`m6s^
*HrE>VeI~@=WX4)!arpF}D4(XX$#)xCqC!^L?;nlqJZNuZd5t38$J|u99+o*n}7PsayQH~D`wyFY
9ww><k?1lorw8Pyr-uOCRZ?gd8(F!pBS*jb74n|LdI`hS-_d>jAm^M3PC`*~28o?4ISP*%Wgu;BG
{sNVfZ5_6VE|2JP40-bm^I>&bdo2sSXme1MSNbGv8F5`P7>I;v;vA%`grSXJNnT)tCY0n&`CZn~u
|OPE)ZHxRWIwdaRQxc~SpnHl1Xb7>3i>0Vq=Z3w^^c!};Y~~$G3~FaL!mZx5^8-vPqEe{z7{!@%S
D{gC(%ogbfeWYx`Jp6;8@ACp@i9@4gk<Hh*jcCN#yVWn0y=-i((lV;jfGUT6VN7DrkhvA^`SDOGR
|{;58PV6ttm|TfuWZ4hwLmLN9Qx(b8vGy+s_Udv^s#AEx?FF}&~vnWa*YoE9K{M~2b5N$yAKH5}4
fKOwbguw2h~;MAu(<qRBzUv+Np`bvN=3=j`~2~NL%|HwwuM)2EWbe*80O>8tt#Z+;*`ZxKhhx+=y
5xC0M&vaMkLpUuGV<+45@}7cL3HQ>M?Z!&&>3C7-^Sq(N5a?(@JDqgei1;S=Lc5oO@QAxdzr19k5
YrN^7sw%5P04Eau||0&(kT9@hTu^+sY>{kK}V^h%~2Do&bxoA;Zq*KzL=ZDqL1Sy9&?WFF_$V><1
Dc#AxEum`F8b6;%Z3^st%y3Cy9i+UEm}6nexslJv02Z^neCNC77!a1G7}K7GkYNx!Wv4APY+V+rM
+N4nZUG4OM9^)w9mUAAIJiXtoUCViV%?Kq4mYD~fJpvN01&^o2}2X%|!`um`~e4(k*o<)y?yBX}v
9Y2hwz1;^E75LVzUynxi1wlT+;gnLv0Dlxhq9#O1(Mm3>Ia?x%hW8KhSJNy-$N=j4F5$P-k5{Y;q
=81F#>5H3;?gex?3_|(-T6HRqO7@49dV?-7EwC~JUJQH?yyp;=%J_Je7;!1Tvx84k#7RT$;!u;D=
ws`<>z<_4eZLoQXz%of;TGHoPSBWEK2y2zr~B5cPy8ra(Iwj$SWTC2qqcw@5hgJ-qUtw*3Pw6$zY
!mhQ{NfrE!-(4?X(lSGb6;2CFCAiu03A-e5!zP?)TQp1=Boa-I{4&xOBuVkzaz2Njj&{zH}?kc`O
PAGP5})*~MK2P&-^f#YMph{K);ep~CtF@%RpX(3;dL?M>Y*kfh;9&3}1FOW(0FX=uAzO{Dl!&&oS
{=Ud=^$2C8-RNnH}XkPrAgBvA#R_|{34{Qc>&r{1`-gIA*dPXzs-?<KkbnrBM@Bj^dTNJvik;AOD
at7?xQn_B$dzGz2JusK>{M;||tyo$GX5I3ZORQ>G2!*fw<kdsCb*d{`7?m)JZIvjTIXckU1WCw-p
9|0;FCMd2=GU5%+zgkez2r3;a-#ub8tO1qd(5{*iQSRiNa6CuO}f<1>Y(+Nxgz&a@c}hBc%&Suk`
S|;k7wr5nhFK!85>iyOl#QB<*aNr$ut~XeMXwGn~}@+otYe^S(8d9ShL(sV-P&@1t|D}0qtH<xRD
srG)@#SID*q>2&XDG^PeK0R{87IQ@xHK-9Wls-2f$5(4nNY-ffeG{m;v~E)%XrUh)(uBR8;_0fxo
5<C2kA4?kTMl<Wr1**V*Sho=4*f414&MBmmpH?~GRGj7NX|EA&6MF+j6JSWo6KQZ=Fvl*ll3`{HD
?z41m<<i9TmBQ0=lpzk=3Og#vF)k!VU%A5LPwB8=IcG6!7nC0!kRhFN;KTsEXb1zez2t9#)9;ViI
wqzD$>i((_s_QD@$@DRPETIGY}pw@(RPn@2D9tS7#kkpmm3ODZj0*&%}bzalnf3!A~%fbcur0&v;
2-i?ov85JK`fV8LlG{UYU;YK%o|cZ-X5(klS6U(YCuH5EbKUM&7}Owhw6>X9(e2X`>(FH*r|wM;E
4bHCfpL3w+H?lh49h4r8Q>+Hp(sW0<HAYQt}vlT!b-17CGqzt(Uz>~+JkazuV>FXdmE*Mscu*vY@
n5YldUTSkQjjz7F0b&lJKlV|u3-&kwj2o4&-UL$Dpk1N!efL|P)mLt);A6YIVH_!+kuc|F}mzTVq
YcomK>aj$5#pxqOzhdKdamNHpfa#=$!(==@+=0<u$J4`IpXW4ZV2hE%Pp4$dg_|`V&hkQ{noZFfq
C7HHvcM4x+*Z^{EHosuX%_YvZ=@>`T^@8)WYjw>6`JoUryJKNoBl_S)OR&sBM#3eg}$Y+A+c0X1n
ps@%J`qs*&lLqWqJDQ76zXBHZH8)%NW>=^{)heU11{ZZ!uOYZ)MrCu6M0k0=A`EOcIP1r^jlAPo)
G-6pigL7^SyxLWLy=9GHPv_iZQyeb$qOU6FCYW25A<EXf4IUyMXn?N2BjBw<ZHcFK?FT+-d$jU4y
LWl6u5fN0S0HcfRUkh3^>hD+!TPv15SC@SfpVP*zv;ke~c_o3(od2wN{c|`>~911T^1q3K^NxfmU
f~?v=mPJ$p)u3TYuO%9Z9J5@K*Anj?)?2fIu#t0;Je=;*!Z{+;ojgD~GjtRebhicsolk{pJn-lsO
UuHNIFMX!=;eh=2GmG+62zoQg~h3ho?s=5RUt+Cq5zPWNR=c5I|nUBod_|_wq{zVoF*&UrcT95S$
36$mCop<bU7=sP)nF3jD6iOt+w}r&`nayrn;5TK@LC}W?$tzM;atEqqu5YEwHLXz_wIV<*F>X8+B
(@y6HE$wKhEYX4D^LGwWtS4d(gEWY<8sC4i91;cMhcy^KGS%rwun;|K1*@WZ>PWmuzYLZ|yy(m5N
`<Y=G<4!v7$v)NJDVr`q%NuRlI4@Z=Kj4M5)Gp-!E%E-GausWu;<H4FI7NfF`YoN|C%%H8j_KNbn
uTePFcGy_Wrj;{S)0b?#BouRlG8pruD8}kWC6GwaS2m9%hp@Fubym)|9z1M!e^&qV*5+id*OyUAz
6Q1Q%RNDgF`A<z?OS(RdOQEHJHqGvpxUocgQhbL|90eWS9jyj$@RUOY1<^{cS*+Q*YT#3%8#Z<)a
#PmLXy$5@884kc|L8jKP`osw`g@G?g2IymG92l{r=8HL(=5pXPq<GctM3sZ_6?Ugz(=_fcO642l#
<s#Dp`y-PMe@`f-@^9+tT89(*msEZy2Rf+j@ODNnDiHl6clO59|B-6r5o3eqWxoFGzQY|(;KctbZ
b%r%CBBny#bJzE!Pv+RG^-37U1rxBb{H_)EP(%qh*<o$PiW!2f|I^1WwlGJ&XWY<n5kb!_zKRY04
2!G0o4}xbfmUqeQLyWl`tZI+BTF2=dS9>lvndVua+yTw1dtI*D^;Ug%lh5fcJRSCN;>?=+Jsx1&T
k`|X?OSq><dEZIjt6m>jPpAS%szKu#}9_ailcsqY^GK5VATY_2e|_03cF#|dd#)Ruot(OQBivR3^
4OKUPBgU#e<zybNp@`XYuTLo?WHaiy0-v>9fpf2<Bn0cd%-<DL15yxF0OCxG3^rN}=Y6d|MWFgp2
I2i^d1NKJMY2ez5b0V&_K6)w+uU7W(VrpasQ|;t8jZF_5lcRR-iVhKa{jUHiRHo1(4-y`harwSfj
_jeuOm3%@gq<oP9mTw+JsB<lx0*bx$G%GH6+3EkN}of>3^bZCT|i>minnA8_txOXaHrj0y)mq?ye
=sglJci`ABQwOi)AxcQjD5$gMTyGOd^`v5;tY&?i`{Z6`Z&w=l;RkBMn016NQ-SL(U6Z>Cx*z2=U
(qY`ZkFh!j&)aP9|4|rGF|(aA&W|8V`TzBUaz!Z&PiQcR#C^~KMkHXtl&{(^Ck+V`wrW6jo1Qo$`
=es#g^*e<~VTf9f?I!!GCrxYSvQEU{q0-ot%8DuxHy__n@Mns^WaZ+OLs5GkKb70JkfExsqN`)Ip
T2#h;=0`m;3H?7*QduQ7#hJiETN5`{^Wkwcx8u5~2&OyAKPgGJ_`z*9-Cu5$XCIea;$3HgMu9I0}
nlBHLgQ3zDOBm%+#nbNcN4b=_Wj?=(<1*Wwo9lS~;i#HjwYYdzJKg_iC<m0q9EqzWyjmLe{1xJ#|
YX4BYrC#7><kXF8`i0I5D?6pzHhpjW88cV6L`gUqd@*N$10K+3ZLSA@`5SpZ4+S4cT{4*C9nh8rX
{7GdIXfv+=UV6_{u$s|fHC`ywtv7$0shSnQHM?GK3B%WmQGpuK&>>OqI%$)p43STx~|KVFO<%U<u
o}=DLsrb>DCkC$s)QAu1YVuezvQbN7uo|L^T^sv+6u&EG3Q1XHAXDfM)hJoh8G0PPv3;o}8r`CT<
l@6oH`W4+1ZUl<9jFv{XNowB{PqDJzvc;`>G;H=~<rU6KhHVf!RED2Ogb0W+>2O-EuTFLKxyjJ+w
Yk!mZWG{xTh=jU_)AW3YsTC(fT;eb;YgK=R(D$8ssS3J3n9DXdu7~m7gb37HRb97R|cK*4@=j?nQ
o50|pi<kV8>}}9`{WhVMZ3QndCmSY<izz|`Ss?OQ5hCy-RBYuu7+KaZ7@4CHQR$sHi#>fKzj7;qT
_x(6KNB0??{oSliN7p=zd7If#^nG%CQAcCmd_?bkagW;Zh{n8Se%4$BtHK+%BMCOg-|r|z2<50q+
FxDg4g}9J6`4aN1Rvk05Z-}Xt-}F2+f&Ouw7PJU<Sd%LX=%0Cwo`AJWuK@#r%Ufg$Fn0GE{DjmU^
$;4_1ya)fG?3N-j~;$BK`PdhtdAUP!v#QzNW`HpHpqg69}UwJ_0(<54x!du@3;bG`BuQNbM~aXtC
JS7B_hPM?*_Y_+3!y;+}%dTInz$k=egaS!$2f4%RM6Vkx){bN+iqR0bnZD4}cLzI9RMNP$8q;d<K
NMJw2BwXPlDWiNK(e2klFnw#OD`)*q_o81vZ{=nTl;+vV_+i|b?NkYa)f4sbCAmDQWDmT<9>T29R
!8YZHl3rsS5H@|?@3q9Y&(T}S+#j_L_jYdssJ+T60Rn1NEFo!PqGf7-_@a!)|k!({A8s3eGnMgfU
a>3@erdsaP1XZ^67nLu2-C&(?ymz=*qE0ZxA>NuJ}eiYv*FXYqWpEv~ujDOld?0`Nu=Fa?(8)XLK
{mT%3;41JQT{+k7CDT?aVAvjctl>;saX5~J+AfWsarE)gT^IcF(XgTMh?{x(o?Mk(JSy;W|JY+#^
`-wW<fsUKLi{G}$>$=Fn(`~K)E7V0QM?&fxCaHlcdy7zj~Pb3~t3J|(86hA8vMA2eAwhxZW93y~e
|3Quh%+}>5FpnpWk_<p3FvIkg0aWo@)NmoGmPle`#%z`jk*N}IR0@9tV81I}fS7wP)atc-D<I@t9
-zDU@^BnaE=REh@e3$KqjF^9NYgtPa@2RCnv77ZQ)tx(&XINZ8xb-C4x-lP!A}%RP7;;2xz<r5o*
o*nJwTnngUY!@>=1>Y!_DX8>15B?A;ngASAip5u*{3*og*hJk?CS+n@lqmspixobJK@*3M3t~iNi
ZZn|Azjoed40oat~_8LNsh<Flr>El@dAQq{ZAbrL#Sk)bE9Cidx9oUL4d$|rymOL1NmF{H-84+vI
mYmy?3P2ch^EPLp%OSp18lhmv#z;s=3>FTt(p|PuFJrSQ(b&fjeWuYn&pljHdwTnc6q7{|TwC^S=
d$sqbzXrzo_f6jl=1MgpgLa+#HeH~8J+G%6<@~`Py~995?Saf4f2p5Ak7tcbuu5>BF)`ldtMAzcf
Ie#}zhHgVknR;XLn|6o!56t<HzK2ak2VK)L%LmrCGpaM_eYcbkc>&9a&rl9?W(y`9TrlD+cj6Vj2
ltw`Qyg6tset>1l7#d=lcJ+VaB|^K%4soxpWxAToJ3q1_Y=Z?z?doILmkp=PXe45es2qOx%(St|Z
#%FNBPxNx7q7f-Yg?<&o%^GV{B1=sJZN9vKwRzFaBGSEH&mGG6;-eiO1{MVRBSnbXxA$!e+DfKJS
b(Rk&Eb-bco!#^v`uW3-HJ)|2hM4bum23-oO{?c=DFp_v<@D!t>CGkX{w_I><a=u3-aSk1=C7g%P
x{prqVLX|FfS8FEC$6~u5x$EQ_B*?dvG2L#UsiEb|D(d6RD}i=sWfxU9Lu=7oHQw3dUzAgWnt)Fu
NMhN1%CYw5BLx7gmZUeCf>v&PK|`IZKkXM*w;RCG*%`3PlawdZ>lVtShmt15$y3ySsnM)x6yTa6g
Ix)>oXO`j;@M|K3Qc-i*hlLQi#~BZkkxf1ycd5z%l4luvnCuwOJ`@?5-%AizK0R;c-)Jbb6O#u11
Xh_2DL+!A_?D%*4P$*Nt1P-0}M}0#{aoCI+Rf6&ar^Gz9CLUQea)?-N+Ku|E?Q88<8Su@*eY?N!%
~$i=`0QNAT&V>Vq;dXe;dXoj;YFM>JxgKF4U0+$@in2u!Lf)X3BFBnx@WS}mL`xcseE0j_)7B^&O
Utt!bIZ)E5t`KenEaI2vyj9BndPBVNq_k>gMMqU}`8$7U9c`sT2fgK)OQkHf=-g}6(*ZgB?dYH;x
{jQ=94Dy3@mgx;g9#r+DdUgcVm5fgdD2@Nm1<bH#$4chi*B-4yr0a+E8lA#$y??Rj}D>gomxtdqz
d%22}+}a>{Sh4=naFZ^`s3Z4ip5?yuYv7+`TW|h51ZY)Ogv{VaHU+F;3^=3o&N?Q!&~|Fjk$QsjV
wNRZ*=&qGifslcN!$UJ<}VuGm@f;B^O~ZU8xFHmrrY&`~jEZ5qL1I>1<dhv!>l!=U<qs6Iq%!NTa
mx`ohC$`&`eyiwC~s6NzmgNgH*VE2U_2)ybtcWWxr+Ng?DN%h%Zu~b@DvA0I-lK@hOm5nTmDGu7G
(^_O?L+3?V3g*X<Ot1X9+q6=V@84$iYCCSlr<ybM;(g_p|FEd{*f0-e!<7Lq!Y>v7DghO}%&Qy@W
VgH(`6tEP7Zr&*T5}0U8h(n4X6845s{NJYs*bIp2UjoM`!5^EHDh2gev<+8b?1?KHHa-`317nGe9
lm6v<Xq2mY8UDmJjGw$EO}f?h)hMmKQb~g}q&IpDPM!1L`U*lZ5cay9&AnHmW%xgZ1s2d4h0M*cI
v*O-lF(W?Dj^9swyb$@mHt8eNIii_I(aO|lG?UZCnmshHQ_63Z=(Qq=TUYWw_Y7xi4N(fE~`{7ol
+wPk9p1)XWJDg%>jA*(C@84J4UqJH7RZmg%*>WDITk50uy9c1Fi$&$o@ah6=iGYnEu)G#?ylG-bY
m}>VelvuG|{|S7saUr|@4{m2iKcQ8ces->!E1_12DJjRR(a<eEvg9GF5K32VNpP)ZxS^VbX+V2%6
grGY<bC2iV@Di3DC*ilSGuwt`1bE=2mQy4hSIA)y&;Vwmg4yLI&1MM3w!naeWTXS9B0X`Ne|c7#9
>!z;=^?{WitA{`Kha;Cadq8z}i|IhlacP;^)&{Rsog})O!_dY)9z>p>U_xdfLz#l%UvMV^wD)(pT
TNF;y5apFIDE$Hq;Wu=qp-#qF7FZhvD|n-$7JM98RPiP88eT;acu3$HSNV&NpFT^Op6;&7#NOW}^
u8!?y(DwszSA?PN#ryTE94SeFp9aU=SSRGspAwx@GDxQ|9Z(ANOp28us+E?8hKE1d}l6m1627if%
{pWhxI|sfL`)spAQ6s2f4j#6<BTZ$f|8*2ohpeg1tf3sheTg}6)|3$G5!De{2fA+$3pEX``Te}+D
77PKR6C_XMvYaZOayknqOzLB+9K>mG>{t2?^J2<aQuFa*}bNS)LVZc>ITJ!_K)Is?976dlV#8adQ
eBqDBXg@Qb1*HJ`Stl8lw8jutm8;E8`2S;lL&OfQ~xgp#Q}m^+HJ*V}mB=qN;1GZZl;ixP55G5pl
_u*kx%mclugox-1i}hrw>UO()Q5GCdN%vQ|q+Gf^-c*N?gkO)CD8qzkbzPr0-tbmO2t+vykB5R%r
e;(Neyvfp&_!U7|%K7G}%GGRi!@>LkmGS$g%MV@)$Hz@t%XGU;9Xsyv=G7WVL4Jp+i+Lp}^%UshH
t7P>+tx<WOuI<x8bG>w$AE$nxEp{ENHY?SVTL)SdJ6Y0uHwaZoLKx=L6eFs_1Jqe6^X`Wu&9W5@#
|x1LVZ{mJ?z2k0!GIg3no_g0MZ?}HQ5kDguI>9(!)NOJ2)2BRcSqXLGYHA#Asyj4N*`%}5@(0YsE
{7<WkT-%aIVT#nw{Z9nI*fqO7tyBWF&zXU`9_TQ#M$tWKPiyYrtm)&<oCig4fPb&9Gm;6J!aEoBo
Ja=YxL5m-za4tgv9PGLtD^NU9D+K@)myOuy2^*3N&*MmV&@eN9|cwW!WSRwXXTbPH$wPWz(P)|n0
EE0?KNb+AxK-GSg~&}pv#O9>d+6#(PJm;0@R&;$sPoefPci7210GE^6PByFO8Xm_N)k!M1wJGUI%
fkVI?+aFbMZe?;=pdTD`1d|wZ#uW5Io2Azr*nMtzm=$x*$ay`^FXM3$MuN+O0lgUv%#3eofquAgh
OP(rwgC%0v^;9)@tJtyUIhNUY*sL{HXCoz#F4DjV=rxZIv^foFkr+V4A8|IJ0$HD%L4VP^N?JxaV
da2Z(%I#=@O0t4wJHl(XGp9xoMs?f+=YZId9@Py_{g;o{!%Y0aP8ehDgoHwBd5esmXcaungyx#+g
5&hexQf#?+n^@j%B?4_fj%OD7asLl#9v7B+(JqyX<A_*?ocpm4*O$V{2fXF;dSQRLa;g(K0x1}>5
$FvbI;jnI!P<y(RC3~+0HbF~=LI7QTg*&Z#(3$+~aqx&RFV;n1<o7ammj1sy>@*2R#tZ$faVRjpj
=^2pAc`T7kF~AOW`;PoCX<nYCbBXN+qlPjP0TN_3Bt~c>g13<{yPZ9XG-L<BxubI%b{ooBMS2Yg0
2Dl%V?-SGI$&XHB4(GE;REN2+9-P=!Ew&Bm+y~W9}hm9{Nos~u-Dz+J2=l?pS&5oK01B=0|ps6&)
)p_dhq;*qxT>1>+T*uc=!I~_0juZ2Ct6ae1G}_zS`#(AC8~Dee=S8)!lh~p264Cqi3(6v7?vAr@z
4Cy`A&yhaX?QgvNe;c5;d(I{^OO`{UF1$H(~e!!NI&y?sR>+T{xZBNd?h>!Xu5mFJx<wFn)kJU)7
L^8K6R7uNHATA5dGpa1Rjmv_g5lQ%y>sTb^-Qa=9a`2Dk^)05W$N&n?@fymQUKK}8|^S7^|(;q(2
JKC}D-hMbaJ$d_P@Zr^4YB}t+ISf+|Bhl=^{}=!VzVE{GJ^20@zIQO5PxmoKfjIv8^!?F5x*eLKo
jUZ>rJo-C?9k6H{p``tKK)P-BKJUh+`yksTmJ9J|6TdNC;#ur|GV=49{z8HdKz3V((!08&5IQG(E
$0KP|-dW90Y@-e~SY$qJoqmE;~F{i{>Y{XkUb<iFI1hizk)1FXYHm`Z;O+j1=$f)s(0Aj~)eGyCK
i@ud316cOtl)r58#saE9P6FdS+pc=Cj+I5}TQ=2B_{3qPJ6eZVd0pH4129LGfwsEh{TF*!Fvp)#s
QQJ5t$(3BNq>-C3cO^&Q7ZtrMUwvz4uS>lu8ih@w0>7OPg9GwHtqcltBgF%QvH0(r8Yz{iUYNgq9
p>o+fuVAS5%F$Ek5ljU}1@*ry1{8wLa3#a8p#3ccQ=+~&kz{mhPuM$A_sdoJT#~z+dV8koxmqR#u
BsbUIlfG<EXvcHz<3gjs*_@LD2!Af2O%4!-sQokWR|N;Z+y1{3)1qBqv?(Vos_zjBpoSm4;pER2f
@>iS40%7k!MZpVJWu6oNbDr&v9wo>Aq~MIV_jN48`AB`C5nIp?!1^1^)tos}Lk~AN?z!n=Gsz_Go
wSVG0%td7{XUmtBiw+k8%y15dI7jo}&JGc0J1{q6>D=o}bNxLn_ZL&h{lW-HSq`B>Kma@G_R&!f#
Km&$qKPSVq-GC2(1URp|&ThqE{hn79U+$3G*Su4x(M5bZGiEkcqaTn=U_DdE=jY++`RTxLp>b{kQ
ph3IuWcF?=sDA^4DwY%J%}rfTOqR!Na*1ZIH!VIo%C6nCxC0mVriao`v3LfbDz1>Ddpw#-Y*#QGZ
7d-s`os9V1OUd<r*(FG)Pi4e<|Q&XH4`{S-~@yt2HxRGGh6uWq44y<?n65jjQJ}zEw*uOPuFPk!`
#5oJ47eaxqkpSdq^&2!lQr7NbEIDFT7o$?$)eijU|DJo;NKR#u?PTsNyI*wXih4^Ph$$L9i%r$vp
hP<L=j<^VI#iO*p0~EX?+WR1(-CM<Q^ypUo_W%tQ&f*yiStiFB*+i$gBpzGE7xsEEBgC(}9FgX+A
KYMjJ@Ri=#j9(2zipxiu426B}JOch};$#^XWSKfh*DL5z#xnyJ&fCxGUY)b4H=5+5PBPoYvypxfX
!!iOqQyc2#*mPP@b6QTY!DPFP7i;$?m_<aWiPI47OL=XSg=56Bj-cyDD48uL7LU(EKns3P0(smNx
-gAB^1CweU<v;*X`nRp*>`N?B)&ocAon;U3iqQ%>+J@Xd1}l;9XYXboBFOu2Ia6-gHf%uG*T7pIm
I$u*4VAk(5g(SUOb`lwp^7HD^WWhE7^_{y~A8NfYUIbxFeCX4%hBb7yuI-ks^3|nUB?mrbEF&wg|
Z?ddXad``QFa{QeVW;5>NlzA`YJHb7^0EoN)9ZUmNc<9`!GSGaokwa8lT7@FlhKRRQGU>l=xvYOR
nqB2^5{?xegTV;H>x}z#;#Zt@Vv}J0Wma+;VSF{^TN;rk1h#)KND`Uihjfb__(8_%jo4aUDQS8X(
#TAV)23udnoRNAPNkJbIe*N^}rWZsDJG+2Bh*l)7bymz@4dMG-3|qYf8xY}@=SMvmmUb(oxWb#j)
8%C{AO@zwr}%gq$1a6=Y~pgFYETtSf;NV;txfxR%>Kg6SDf_?-sHmXHSVy_m+>gjEHv>SF5hf*SR
F8m3w=SX)~vr$+td(6_W)^3Ljuqan0~rKGYlUP>dB#51;2JX>+~iIkmjaxN5Yi@&JP`V<X0F9YTs
OQT6!-nOH^+<W{l2w3tRD(T_82^0gp0|?u;%}R=)H+mtfJ=7n=37CfyZWv@&R>^**z1U~N=-$ags
dx)7-#FV8Kx4TB^k0aHD?K`Np9<$sOAQgMmg3xJB&a*mk|@s^4gtL-g7z8Ohfm*M;y@cbcG*!KZv
CKfgUGl?knTx}ds223D!sD!exdS%iGDz_yrUf`TLaLTKmZB)U7cy#~*P33+i@~-;81FU)*M2wMpG
vfk`$LV!OGpK+;KPvY&mWFD85f+sGlkVkV>)$tmTW81LE1HibqIH`bsg07S(05zK+b%rB3jv<p<0
)`kA>#KqZq?oYiPyjBaFWb#@{utDx;Y%EzEST#{l|KL%VAY$1kK=+)hgbZxT>C8I$8HOP>Uf{Srr
P#&`|f3K+!E-JDxB1C9~LVM?UqaU_YHdG~1fUav-Rk$bZ18dj5mXdr(Q0$||cy)ea){28KGLSQBi
20<X@uSRirth%J)eQ!LY&X*bJ?xqG~rfGKi%`l&KxOYx}2S+#xpL~$4QJ*V{2H;ZK^i4`L1vW{uG
S0MGi)Hv<NvZtFl?%cs<o!iCEb=&{x-aX!|cb%H4`_%oSm9v!9UK-Jj{w*_c8*StSySi_luB~aZq
#mMIBPK)$h~&D^Odat%6|EeG`S@Ao$6=F^zD~4;lTWr5lB0}U!MHDM<iob<BO;b9lOO;2%`=IgK-
xRb%!fCkV&kDA*OP?`$Lgi%9MB2MuV{s3)V<&|w`{<IVO8VVvLOVZG}&l~aS8@I$F2$c5NAfL4J`
44$ypa#3jhTDb)MzlL&v_M3u9rUKX4C<B>CtGNJ3^(!~k;tDQ3!jJe-f063m3`$0};e3e#Iny>0V
~CQG?(uB=}{Z6x)UBp3!RR1io?GWz89<t`iTmYj5HbtP|gA|6VfV!cJL)v`eCt()$lrG>ItewTrF
%h^TDP@JQI;?Tp&By!g%$*W=Hvu!fjSgNA+O%Cv`#hRD0zCDWaVw1b^r0kMEIH$|i_x(3G6@pqV_
M6>l>t^RK^%qk<=zBE=@4szW)-M`_Dd{uz@Dl2`no72O<0?~$jFWUGAj@T_M%Xbn6b_$kz|4nDYn
MGS0Q)?<%~ornxP2vj8_e@ju4);w<+cg5SrJTq7n26Or``os<E{vSE7t$2D)yOjpJlRza~M{I$iG
$<xs{b=lu_4hH3(J}Kpk}JMgJBoK3Lx$O`92w4{ES@g&bZ1=Az4rCBdu=73;c2P&LF`<IcWvsRiu
1D3);OeJuH?gJ=W)bW?;SG3DdM=4<Ptm<pC(blK?I8pRnURr~dBemfKr-jq1QIVE@ZzN98)TQv0x
t}<kG98x_OTISkpGQ1OkFgBP4g+Zp6ch<f?KDbzQ#H>^Ztqwj~nLOD!Jn>$A%DSa6#m=g-II4?s`
Z;uR9WDI4InXWRPB9GoHk@#(CWbbhwTS9A;$tbi6}+~H6{8K!Mirs&RB(l~PB&V+v)U9$ci!Sqsh
n(eadp<FWU+uSWVE@#-tPF}?DP*l4^Gz)=Kw>~ZUAUaJYDbZWjlYwNh5oMbtMDB$pH0Thu*`<%Sh
-tPYu4K?%utGUzYWlF_rvF^H5i+VFld-)T*(L_4#uSP4o1w?`_GSmF1tV+?(W&lCXK}8V!h|w5y4
-1@K9EsH_c7gY4#+%X;G3Y(m_C$e1@O>!ZL}i@K(4{k^?+HUXd>{i-VS;Z4cXSrGmjc)U5*%)SZj
&{w~|mbIyzO>`c831cH2k^AN>NzkK<;^5$IL|Oy{c_k&Q%+dC0EH(NaZ8+-yQG3<YF~WpiW6CdPE
z#4b<_(Z<GO5z~1Co2B@9yM4sjtIqfB^4oa{A6Xjmi~YTRrOh8++H?sCV5Jz3cwjy(`v*E-GC}^d
h3I^d4Utlzu*E`08R!_fS-`d`Gwzh}zvc<LWx|7wQ)Fq*Nk&oeX6I4to8KB1Q6;Fg#S~h)xWs8T2
B$9gRL`fEM6Yn_PsY&jL;;$-Ub^Kv>Zg9^z-UU9w{v?Kb!Ny}e0s+%}WX+9#7$#7><9)^Tdn&8Mc
S^m9c$f`q&^`!$I&6}=&A7)R}If-$!b*C?r6g^bzn4GvJ5qNkNs)*qfe0Q~Js4p5#Yfp(cJF}nd@
O{_gMf78R3>dnuXGa1ZppS8vtk3e+g>qbz_hQXnwj&IiKxvV}v3DQl79x`aZtuM#?^lxkUXb&%oh
<c$1a0a8f*sMNb_<GjWoTkl7|F!|6TTcEO%ENP$Za6nzGcTVpC!5blx@Imm;1hV7sCP|kyZ!%S;#
OJx8gkWU)Ym7y*)`Wn{43N5e~Q|S?^-uKe0&31ExS7kZB;m08OM{6fqJ$bxZ3PBw;aaYwS99|i~n
Dy{4sSoPij%07=pu~xq7bfju#6)_3CIoM{gxZ6uOGVk_M&rY^u`-VQo*S<_ZclE0=G;jIO-zt8|x
bBGg%G8a4!!@38PpevRVRPkz?xYHPs#HR$ZFglBlF`s!A?eKoD#Ryrjp+Mu34e>ZI<w-%h7Yhn9p
R$ZD?*bNScQ}`n8l(+I{{j0(t&sWnvbblMFUHEe(CK)Q+ugI3vv-w8;Jvm&=*ebxf?5z-z@~+!6R
8K@gI*&#$Ug=q#t0MrE(T-{kpH+FNFg*p$^ZoI`iXAFrTzwX;*2cw`1s=p61vvdyW9X029PA=8wc
(ARAn8)&@vRw1Q+oO2P&f8O&-+S$81$D?RhnwBXv{Cqo+2WWo<Tj?4(gZAK|(boIt|CIc`oDL`P?
DWI_}hXFzE%_tus)NumHx^*vMebs_ffIb`?ChCL9Ql$Ju~V&Vb<EnHbabl~K)hK&s`kwX=S9QK>e
NL1rFHS7pspd0QGDHR+wFu4#HvPrVE>RNV=_v*qw`jj*=b<G=)KIv#8U)%8@UvBmOeUaFh~m83&q
p3C`WoyT75Ee>!~8kMo7QxWQzROJ{B+xML|{EMu3D{OY>nkE+gAav{+$&(}srg1u>T$$obY+Bl>g
rYMiA$?`6SuTb20O$Ff^VlpVAyII;hip)z6jY9iN6L<lOa-C17!8J(l<3MFE!~JR2OUzxw+6QnnX
xfTbF!$6`lH8fx9!;IZ6B&`v@DxYtF|3kXZ6a3>?UM6skrNRU@RZnb{jf^zXqYLGO!GSDl1@k2dT
8TaWKU!3lw(jF4rp~omVq$IWyHvwC&ww8b=z&rly&sl;pP(4Q`fR4>-oD858b(daY8TBTrMNJ}!b
>CA<G29_PXH<DmGMjFWlJ$;e;63*y;?!@#{?WICzwvvERMG{awiy_Ap5Cfc1|&(QQ0zD$?%o19|s
>Hfe|j5GM_uThJG%3)X>4ANIdi^GoO7>`Kx23S6z7(sE9P9?lr=W+8Ab9+L|>9pPX_1E(ZJ_xIZ1
$z6c0O8iJzp_z&bDGRB)*_83c$Z_wM>2jbhO=}!m!Le8^Nb=`W1et;peGHXaPId>jQsR6IObPP4t
;k5WBd*S4^EQVwWOg;DQfa{l24L3+5%spC2dNCiqf-VuPH-)MvpN9EAA1D7k)#T-1FH-jseHX3^C
SSi>4c&2Cb{hdwPp=^$nXuw|<)x6it+)ebTzUk;H}+F_D5N#=$=qAn9W)z2J4qi6Ezxg$7VA;W&X
9D;)DGmKha!DPRLiIBzI?i*Z&t)qIgq4q^`Z%8>yn85gZ;{4vQGEJY7j@nOFyVC^U`GDm#H&<c{<
9uYsuBm^FjcVKVu4ow9WPgO|q^X$i>OrWB%@v<HVn@w)7+!4(tq9F=*#T<j0-=xWv-UvM9rd{+|v
k5%L`4;>lY?1;O_ySiDfL$je`kLiUSSIxmR);_0IsNA7_3?!n!7rUq07DAPtG<A^d85BzNCWxE8F
R|7%ff(gIbEJ-G~HMo3l@RA`hORgIxC~FkUu5Ec}{{T2eIO9gfSHtFmE%C$w(V<kzs@*kUZM_ku#
DYS|>r+Znb;uor7RPM)DZ5`T+*vjDt?=pa)N{((46T*%M;yDG-1IV~#qE-zbk8tQGpiv|&|$IC}M
V@Z+14(+`7p$L|NP(E|=|*xJxq@F?iDphfQa-^o?ylBfop4f%|5w}E?9ktw1FloBWS5u;FENh(lG
;7Qi<xCx=v7soH(zJEP<_V&#&1?5vmK2e%rnv8GLg7Zl6lVX}?N##Mue3B)oASl0cuBL_!c^nMK@
ohRBTfoM_VhThHP|SV`y-z9+aobhk&b)AEUbr(K+?gNl7%AuVjopJ`Jic-}n$JCbs??oT>dwl#a_
lpTzWMoB9bamDvPZ>!C%_=rbEdrAcKaYmMk%28H@MG};ez9(NV)<97b4ny_}lTT<I}fq1_)TfzA$
4lidw-jI(={uft2e2l_aWk-w1%zeQE$9Rr{%Yb{F*}buWe;1&B)uOiSB^nLu(Nc>o&@6F}t!G9Gb
o+N6(nH~1Ur3VZtDi7?KALf^N7m$*xcw9I(eYIhEH0db-Gga3Ma^5)b)+pxR4+rT355C87(?sgkN
6CWJxn=kCY9r_DGZty@c{9*em;dCrGkJ}ymySKCdxW2j%Ot%En{2Dkt@30Pb4?c5PBJhSCv)IATz
VxrNx3d|XUA185^z`;0%QSa-8;)zw2WPi~u}EoLd%K&#5ns@-XU+2$bm+hf=nH!E*gMlS!Q7#P4G
~dc^d3*qE@4im^LUp5^$s>%vW`M&8Nfc(d%X8pderWAHU!kQd&E=Q-BEzLyPNK@p4}sP-)#$4_jb
D*0#ax#6~AJVcFQg`ziyWHoIZW|H0@WX2~g>ATLJ29+9ieD9W@v((dj+z2v&ACohOanv_zfmZd>L
_&G^O?QsFm`qSNm2w7@B0BK!t`6n=MjtA0(N6oz-W=2vv8=b!TSURx+rcYkj~PzuSrj7X1n_IP-^
GQ95N4HvJwYeQ;3K43`u8q$WS+1;}sea)0BB=7RPe9iC<98g~|zQ;DGuNYvjt$7?enjS04((5Qh*
bt|B9UIbqXI~)g3#5bIhLE}zq@A4unW)Zz>eGg#rKj+`%Qe4dcsmZLuNdF14eDzKs4%@pZSU^x6X
AQ@>+u=Y+1<2H`wpPTj8VNEVL3XR(w5$V1F73%NF5<9JDZ*`y~j2rIu8I+cTc8izqcuW*|s5dyEN
hZ`+JW+bHaBz?mQ8sgWdM$F5OPof>cF<&i;mc#*V^r;Re4P3wCx~NMDQwJG(BZFUEtNJqOfRAi}-
_>MJnepfXoqj0%r!P+x%yyBgDJM)uk}9S0RQoT*)n=m!jlWjO;A_Wr-_p0v4bBiX-#a>`X?3?Zbh
teNFj97pT*KF4wS*xfvag@Q;(f(;T3L7Jjn{_n5PIdG7aocCp2sfYk(dS-gMXL@@2IB<(OGlc$_A
@zC{LO4GVPiIQ#r&QqVd)|8;IygNPk`nqUvvL2FIp&zR_uk3zfgE$DWPZw$)K?%}sr>XzAl)D1O6
8~L0_y%KS1Lc{UG8geu2g=;$NKvt{alIsjP({Lyoui(=jZ0|dCUrslgIZ&`MDA~FSX|<r)T%X__;
ZLo-(`05`1@rpDU5G`s(cToLAtUEGB3D0}uP>=J+Y}bbo{^k)JU+eGSIV`SUN*sr#c`iTv!b@XP&
iu0(z=M1F6if8R4ITguyUo5l&I2&TyW$t)fI{s48Ys=c+j==mPxC-iI<jqVX?bOX0|NS6g=f%k>Q
+)Y<?l^4Y_=#W;l>)o%5eaPiv8{yALyHiH<bmOK&#XBIUTygn6#l*B)N)n*RJrk5dqoVY76_t~8p
2Aa}r<8HZ)XcN_hYmn(sPi#PH*ub9)1@h$K;@5UgatKhg<?@ki3oMd7-^}4KLC#xKR<tKE}Ri3V&
6h&8y%17nuBqe%>%0<*6z@iiOr?!<j`%<bHlGc;O8Isd(-vv>pGy_Od)vb!iixb)WyftAffa32S6
7AX1}$WZ@Yd?3aNt1Z0rJBLKdi-ccV~geq++2FAGVyLfZAL)C8q+6N}j=v(=We!{LinlI3*SS-SA
d4JD`2ncOffCVJb5s`nLMmI~<+Zlg-S3G~nz!=s>MZ{0ebKQ=BlyWImU@qd)7x(?p85!><Mz1yuI
&16l*hi?0{#_$kB`!URBjGc+GH}N0zc-ZV_S3wWW*%+i`-l0C!lJ4Nk5p`i4N%5h)<;U@k3hNTn(
$43A06z?;GcLKJ+23iQDX#&#kTWG{&X=6yfQ!)^E=FzAa~KquRIs(pb}MA8hItT%L+<^!7UNL6Fs
SCxt(q`iB};%-vYY8`N9%>bhjcs4liB4IjZ=U`(JYCUfg{2|H}Wh;r0I?U=a)jeUs&JIcFn5Lyh1
o=_4@Uve_lMb>sMY}cl@nkfXOKNQqN}V&8~TIW=ivoZD`%pjVD=NmnNnNJWz1EEiefD9O;jU`VZ|
M9bsDAM?rruMqKa<3Xm)%*~C(pN=e^{$$xDs-rpY>g95(F#Qwnhm(bOatOeXBN*FodQrD@yVzvLE
#w8_rM!QR_@}Aq#N8FPXq9p#M;aEdGaU7wS%%C_FFQXA=VjU8GMh)b+kwmS8AsJ{$*rBoUPaGHjq
A~GL?p$>#V7!eG?C5wf9(zqwAoGfaA-^96$CdPN-0vYbMJ5&|OJ=1l!Q!|c!`Ew|zq<iOeM<xM@l
FlYtXZqYG-5b4VTl@<1okYncQL8qB#G(>W@N0HVYQ5{N%<{fl2i;=D1&Zh>@|Cp;3l(0CdFN@?BL
o<PWNj1YnY36nHcv=%GDkQn*`*VDLKlNL!?Mwtb0Ngf|NFFUJ%e?E-~g`XnD<B^JKlGErO-0217|
~5R)3?Z_T!v-ex7mC-mcj3mTPe$=bxocX@WXOwbx2LeoPT2a0S%nn%iVEjhVOvgv`FYXaY>^oIKd
S@qx+K|f6DZY?66NTyRxwd{ypT!Jl`DWH)H+TV1&q9rl^-i-q3*_j`*sdC^%<lcnngtpy+djTIV1
v||-+YaGEWtMsonLa9IiI2>b?4d%M(Wz-b=RQ0}>fQx(`udkAZ{NMXs4=^A#i`|W5vM`zRF1y-pR
u_sb<D<Ojt$u;^K%(bv!%~wED+1?#3m?gZ4x*++2M`NUtc#zCibeNjyKKiNFXoVxrZZpo1Yhf4+T
3VYnL6`Za$`5^~|)eiQXksy&e6Kv(^*;b1@?{ujf@JwRy{J-#K@**%?P(>I9yEp`SCIUSiJx;^!}
pb@b)?YEgLQnX(Ip*|L+1&{UTKj?jPke!tv^d8*oH7(l>&u*j213N3tx<AS1Px~SwAugo+;t*6BS
G%A00cyJ-L-}S`4hZqSL#XUPUY@&ISz=>EbXk8Ob%}$ODbUAtZu370;L`AA+mlQURjA7&+!Cs;{A
-hGbI#s=ZNlgB-2ogX6A{z6^;UN?Wnm`VMRT1Anw_-8{137)cC(;EQtFcWj9!nLPvc4GfCbubtGv
1njy$J&lSrevx17}~doSsFseI5E5b5A<B%i`dM%romnjJ*b4`3-Rd1KlLcsq;=b0VD@p4@T~y+OW
u0(No>4WP4$h3Ri)ca>FW!J;1pWt*iDg7jOOn5|~R-JZM-2AHpX75GKo~9i?5gTb{E6!ir2+J^33
~7G@73QJ7ulD1wv3BgXgH1S9m)nUrj$=Q22AOj_{p8L;ZpAs4cQh>gYkvcrEuk|rGY1zG~=Q(e&E
ZAc1YC$$rQ^P>J#PG&%Yh}0y{I|*&wKmb2qyt#Pcp3hqL)>=<wEi<zuz>$M0{$q!#!?+1JGq(<ar
pSS8>FS_13^jt(HLW+u@1r?~XQqRV`<_Nw`)KAD%h>t#Rs&b!Q3*4?Nwe#lRYiJs9X8OQetWcDh&
?H9hGagiMxj4g_W~3VKVf0Axi&%2pA)1jT#=4GF$A<xbt~e>GB~>Bub<#+6uc?y+J#FQS;dmtSoD
P5;OK8b=M(D<yJVRQQt%|nF;;2e*pjpB?5ZfHs!JpNZRCzxT#g)C0*P;#-NtY>%W<CCK1I((-Dfg
L%y<oRD_9Y3hWit3_8sKp^cE;4f-%^KTlZnhY|bx~1<V>S_W6`R*Z5Qys*NabfO;3M&UT?XTdpsI
V9F3>&(89gKbnAxY8WQ~RjD3{1>XiuM)uv{J8FOng+V_(QitwYHjQs7%n^1Nl~~lc+wddqT+=rMd
>r*GsI3Ln-vO$>2b7(R&?4efw&-~C5^7y%GR&M}M+Boi475c9?E-=bbD?O@uqXU&YrnN<Z|(f(RG
2CbNk;3%G_mm(L>4O1QE0^+^DydPxoksD6CIw=htbJZZC`UJobN0Sne$M3*8TI2Fh}H4!O=D3*am
wOYy;OA39szv@vZ7sN&XwgU4xbrR7QrRu_wi})@0*)@93h?Q8D+$QU`%^YC0N3|4c|adp*3nz96;
iHQdg~R2WlIb5;4rc>(wY!dh%QunL-M0q?zkY*LT|lmU}qnq5&sc@+2%{?yTmuFF&uDVJuuzuQp%
>@k>}4h+(6cf<uc>2SJ0AD~If%n=68#HyZ_936&yJ;Q2fVGRz{SpI<;Lo5`TH*44sr>@W=1^<dm*
W<d3)Tjy<Vqt-rS6I4g!R4usKPt7R#i~R7z@^BvS;2>?(~)~19^SXoPS-ZB_(GoXr2?HuJhoruYd
GSj<?y(|HG<b*LrjhrRLOOc&C8YNXIKOv*5tXUf8a=_auWI(8qwe<q#)?;%7J#3pa+?3)aWgkr$^
`pI#r0X0@_L{Qc9>7lYAiuWLpMG0=TwON|mYQc+A_vl!9KSD@-bZZh+Hl!j3r%ZZ1xV%VJZqci=U
MaC{~zk#)J-rLf3yJ#P>yoQ0xgS(3&m0n9MSq1zoTB;U}}bwNwboU+omOE2#%F&8lx$U~CkJq;l>
@I`UIPq3+OcviV(Wg4^N4ct_@8Qr-t{2%Sc=j3sjki#Dwb?MmD@fQo(9S`ATIj>aqMICckTh0}$5
i7R3l|z_!mz8A80sSAg>F#J?Ib!VI;y$NiI8Z1p4dmljTwz-CG{FQuyhct7VC@9^uJlr_XEP*rpv
=B=r>mb)JmeAd$paCW2t@-)NvE*GV-j;3tNmhh!GvI^qpt5hH=^GA@`TD*Zk!I0{ix@!_1v3U;mS
JCG)TJXag<D_osrBwU-uXQ-*JcV$ou-@)r%)jFPz9gE|HlVT;-KkIh{+!8PA7P!<W|SJJOs=Mg{D
C83iivfXZu!pWtMqeSot%>H~(Z3bz7JPJOkWv)D!A3hN6{?waxiC!O{iq$)gH6YqBaRG|sPCJA97
8$x<ZimCU&87<p_tFPiEPF&|jfn=S*k!WV<7>k!ZTlRr1iabhheJM&8Ju4aP6D`KN?a^`Ov#B>=u
|Z~=1c!Z~L~P45u}%5?!4Kbj^G)!Nizh!{ybj<eYi0g&-0Sf#`uwkp*KeNx`qF;?-ud|Q*Pk!m@T
a<^i+07{;x}~4Jv12dCp5_gG7XczM7+qWG%3aD_V}pZXo=v6Th8i$0>rS6KaA01eNJ7a2cb-Lt#p
h4B7PX1U+w-MQ+WMupT^<nfkhn_16zfG+L2(-@pMdoxAON>Wd+BfU?KXumA{|l@5U&CX~rMfDF-g
Tc>Vmz3xDcnIP@&ZV?(7F9XZn1BE54EX7iTOPqEwR`JrQW)MkF;&<F)|_GqNC*l~}rSlJ!pT0OFD
S-qq`KR>8y(H~JOI)KFAK7Z;E@?As*+5`;BKGP$U?ts5pHmAp`VByI#UsP57&tKlqbs-C1b68_!&
7qSSF#i(wQ|_VYyUE$!T=g1OQ|pDhZ4`4{&vGIHE&#l7a(mM0S`mkf94a!6zgED~5&Rf*YO<EYs?
sY{-tD*y%HO4{Rb^b+Cofhb@8qr&*Xi)=ZbX^m(7}km(ErD~jnF)@kba5u3!LV_!S7BJ-EbG!WlC
db(}L09xNZog<EcnA&M-%OIO73<OgOHlw8MQ`%Xi^Oc-#WZ+)>e~Pu~K_QGe`SdkL@}ZyadyDsTG
yrr$*|+g5jA^&4bAfd)rIfl?FnDyv3s--<r<R{f^MooF>uWf?BW`~y~GA+B5VYioX07xn7y*E3sQ
&zx&`+3oGA**7)&dul4SjHs$elNatpk)FRn<r}R(@*RLG|2?XsFBKA5Q$A(7HlWyV9%BMHzjSpM_
Ge=K5s`}rh$Da-ZQUL>SOrxlpUkX#y+D6B5_)aFcnf>y%V#edB%ei*Z?E~vy@nn6R(dz~#loC{<$
HuLL9n0FwU>`V%mRy5kljx9-$kQEWwD&IEu~~n3SB5i^(1|DreLz4*2Q(U^g&1?{(o;g*6ob9_ro
G#*Y34yfO!=EztG7<&TqjJ7##5eY2f1J&pi9xHoJ*U#cm=gCs{`CFya~B1d9aNW=p{@A_`Ci&Hj$
@j99Lr4xt)f-g-)IzO$ygS-DpYaRy<t$E(^yZ)o@Yqg1bLyZ4^}N}0u+0i6?@+%O8F<tYr{kU8~F
YyU>f1@G6atb<k0l%?647mk$V9MbM{h3no<H`qkseRlJ0?V&fd^1|Gl!g7EE=1cmjji!!35XR<XP
^f08P@;ZLjLJw_IArF45%O(J*BWuLz^X{hfB)$}@tdblUSPhH7Y!!2?Oe%*ji1%l;EP~}Y(?!Duk
*|OW4z8+SJgpE0Y0HaN1wg;>9FoKpvQF0+fN$I9+_#m132Sq*b)X;$%ixs$V(TX&$+~<%}iS72DW
jQrcmqbYB1V(BH?S>RdJn?tv&IBdu)&}aH_dk6<^IEbSc-&1BMH~jzxUc(|;p_Sp8cV{MWL}XP=0
_{D~|>&BSPzC~axd^}(T=_)g<TGI*S>XA2v1mCJ;r?wGHJ$KBoA`&W#OW|ZvA?Nv*NK7yXfxMNa1
uJ2q`L$iTrL&@C6QqX6gAgsp(ZFQu`t(M?)1X2PYY9&w$hqQyGMilI{^D)WMuJ%+6L+}YZN-(tex
CTf))(!-u#p86HgP2(ZN1S{hEGk<Ep`sB&X|r&{wCsu-*Z8ja#AelC1eA4kM%AQxHQSCUJ+4KX-q
GsF9m*H~4i*+92?>fFK-vM~h{R4aE?20cs&yJ|En<Vvx{*777cU9MriLD_f->tp05V&MDk;rIM#C
V_pc=_K{<8=Jo=tW1p=_@y%z%~T=NI>)nXL)-@?w*dsOrp{ROR(y`8Ls>mtre}8U=K1RIGV6WgMM
*qsqMzGaQ0*AE#7Q^L2K?E6fAISi^}XQl&XyXR@y&7Yv_?*Vz;3&`P<OZ!kjnRx0XLjmva2aJ>pq
geS^luck`3lmf%X*6^!yak67icKS2=ynpIjp?p0>w1U1Lp?o<6y30pC&a}Q-s^fIHeq6Yg#fxQ%Q
fBpdNzv1N(@}Js&ZbA@O@j6si)=y^gwe`DlBRpXkVCak9rx#Dfqu=dQwXc?VI81#*fYdzv?p*bQT
!8U>ssDa*J|PGdy#Kx$sMd)`#3Ind9i^3s3$cU9!9s;wvZuo+2&^vZR=l}=9LS7sufnX42HUOTSb
$`=2q#;fvrmE_GTyO5=}OrIO<2#4bN(_TqJWbbi!}YB{Ec`%RGGE%JWv9KgshaQePV1hhOLUwi+R
P;8+oBO!is?b~0nuNVp7(_Et9ONh*Xo3pT|XNbNGMeM0vKwA#QB=W>tqAx$wA&}Sp&HPNACA81^;
cZinix?LAR$eM~iQB&gQfPJW1#Z#f1Y?{W*#n4AQE69u`c()i=gH`ZrjhY~AZ)9-(+7`6JDIdD<?
;OH{>l!W6WL@rUl8a%(FKsA-!&{`<Zi7aUhL)MQ<yf9!;#KY-!Ul;BGmmR;-oAeF^nc>FzZ#4|`G
`$o(O;eVXx}fB$p`X)32=V7?#qj3Pu@QN*G2rlx<p}7@t&b_?_R~f={M;}t+T*_x&#pCeG6QKk(b
QF<1molz3Aku+pQ4=+6rQOXFX-%Z-S@Wi4zFr>8p3ldfti;Vkun>U_NbNo@XxtnSl_m$R;;IqR^c
54HS5KjvAO`0*sZ~+yue1SMLIo0RY{zBGo@%->honOK+>BQLg8Xz0R9=FYTGq0EvJ)me*(^exl>e
#r%B_;R$pL>dwSRRoxy{4qs%qj_2HEGR=~C**V8p92Aiw47?9VClsYa&G1tSh*Il_^Eomc%|CQ*o
&=nYDM)6Q8Okz@3^?F#(mYq6Fc`Xta6)N1l1;KT+q%Nali5N8nk;Z3z06_eBj29DAemlNam=O#=3
0R+-%+!IHUOpX2+tn@)nr)PLF%SBn-osy^w`Bsq>Ve43;coC%ZO>2nC|IsPhVWTG4`B{J7R}u3Vo
bNsaNkBi<E$ZoO-H(g}u)>lxaFIGRlnM4aX}7yJvg}3^O56#|=Hc%JNwZ>&m<|c0+c__ew5PVB0k
j8Twe*3{P#Pwg;7hEf-gy<T~Z-2@R#Q8GN<JSyZ)&W{q(8>g6*ZhjwVG_zEu)wV+lFp6Lkw>99(x
TxEHFU+tJ9(lG+9KuoGY<fe}3F+*{qMS&QNN?m1h^?d6XnmJxp6qbM?vl_F_ipPX6pnrqbVMxzL5
)@?2UV+vfumYAOBm?&luo#3xpmyf8<34aa40Qa1R>J~wwlpo$)f}JV>cYA8IPp%Yp#&MJThMiz)v
SAZK|=w_6T`wFstXV|yPn7S?G9*eFd1h|98zZIpzIm9;Y`~yXKeSb{|0&+jR1%WTdH}tbLt^oimZ
xmOg=4l+lGr@+pPfsSyQKLOirG&c{Wu_@9qM#%2rjX?09gffH<V@g@!T;F0p2I^!B$Je8Fiz>X;_
h^AGc4Gq36Yp(|-J3vlOIFEN<URVy44=VuGmCt`lu4<IdZ)pE}m^gQa!d8f(aKMX#9>B=jsX{AB*
b~I4UDAsVtZWlw$F>AuR$l|~;cFK+c;{<|Hkw7v?)$?&Nj3gfz36M@>=EO&9dH{nWS9aqO&+MuaC
W@XUZcrMkO9o;&lXJ36P2@Jt#})b4ZZHbZxw*QaI&9%ose}q~!`4&*bnAf@8dgouP4A}2X<YVFj~
3}F;O2!-<6v;=DfD5P59scPd=Mnn4SXtT(R0_lrp26~@sazX+?4tz>~~zI1&>5LjYy;Y#zz^JZ$w
qY;U6Qqm<7ajv~NDMW2LUKb>fwFSPP0`dnchE#=egoy=|BSrpp!4epBwq6XOPfA|I>_FdnBdih4E
1OUbNU#l;63EQz@R^A_P88>UGnt96p+Th3~yzFGq_>y-pYQSf|aJgwoFw$5@)l{Mi|E?Sr~4J9VX
lEjcec<8H#0{<nQ?O>dlau?n%aMVjLPG_a_PQErW@5T5XM<#EZ##p2jaH$5M!L#8UiTCPips<nvL
n*?vvMUcNa4w62vx#Yp5A*|1hzB;Dua2_H0j5O%qaiNvrMo1!yC+GdqBHd7JGrEIES<KEkBpV@ze
oO7!MbVP9V2w;U3PrpM{V|W%Q54qom#j&>Tt*HW5w$Ba+xL{48dZBI)`hTy;@iwyBp)@QE%*Zopu
@dFybMPEkCh!Mq{*_c4V3u3)R>ub$mDAk~+liwLcCz%UICGL*=6?&Nb1u#^EV-M6UDK6NeqJ2t`U
DCw)%7g^B6rTjuz3RV)^?C8ek(?MJ6)!OU<P!<$KZM0CF9e1;gffT$7HGkW6f&C7xqtnu74Pf=KR
BZlR<4cF)d8`w4k4%w^!ZogXrNg!G0t6|S5Y8{&5F5_w_SSA&%^z5&Mgtq+-@l|4!iHFfK$QmI<x
6tj%B~2zon*LB>R|B0I`jH=xTtcFW?T@{X9ul0RDME@}i<!FUAVkeKL{B0>d+kzfx;a`sF#=DiOy
`8>VLCf<19F6-jd5W?sSkJr2Ml7!jtrfG5$~S$l3D+aWJK)&zIkzX0hYEj3u`Duu_pc+P$0d-rCp
~xu`4TCIXNx`w;W}KqM5K?xA!p;rJft_q^X$1Kp|3rj!7Uw6Fa32(?m^?%J+#Y2X&opkpDEi3Uz0
zNhnPMogb8iyBt#X$_mXAc>P{+6}Ag$E#8&Zz`mMASA0G7Ta2@i%>~4uO8BnT8Am5H!cgO|$mSt#
3guRpTj1DDi>6rVX*Sbt-7af0i^}992nuD4Ck>=LYnf%6>{hoetTfdP$}8ulm9F+obWS4dHSJ9fV
jFQs$7nnLa*=1OC#vdE8p5vCH>hsc+iR#}EvN5xTJw%B95}QgOS<FsStYlyGM(#HNGul-Fu*T$rM
sh5j)&UN>V3mPwUcTk;#2j6c0kel*;O`;s%A#nynPyaZb36)Ptn}61vgk^ewDrDT}&+NJGUxW{jN
7{b+}*XVI2d^fe3@nbGX5f<iz&2ct~BP^B~RGEH~Ny-~uz3zef_r2KI^!U3&0%M2A_<;cPF7H?U!
%B_hy{?-)Xsq8xsh`W~vyDA}IKGF4}=7S?kZORe*p=NO%H=CT;7RE;<jQ{@9Z2S&^aW2xbn_idtE
y8sh%_txFL&onL<G1jiMsZHh!iRc-&TWZp-+C2=U9$+oh9cE`9U}NLj1eX=_(du?ZK<{V(>zTAR-
X4tPgyC*AuvN!)j~VOD!Xbv%ZG&{V(;Je1`gWvEwS1Ts>r2wmm2wDNVxD!;AY`yy8V*xHxP-!vjk
(Q5+eTr?$s}Qum8p~UfCTwjvWV<{tLo^oat0*p6X_GPDXcOJ)TzoUBgAY#y5H)tLNVzx9;*lz&2@
uDr-7+C%yL!GVOXJduwi+u$1r6`O>Iy+luDgsUlM&ZHgpq>PAHfrOeqbyEz5&T0&WeyvlZ@dA3#N
Gu)~wE`H<64zoBkJ*k`UIreWMYlF{Upwo|q>!6H0Ewk90PH$kD9N#M}4{&DwUFsqyO>~fyK%+&$)
A0PYb^&TtJfiz-rVvb|J9f(Qdjbr1lfQbQsYE~WAxdW63U;YmW5rRP
