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
c-ri}347Z{wjlaf(DHK!h)9~GWLaS>&&al%_;$Q}w$q(lNyCOnNJ2~jYy#Bcbnb6|XR8$jl1|+HX
69W-kw~ESI(6#o=hv<DI<3>i_$sR|d-J=kQM7gMPY;&W;=x&7JjjacXnt2;mc`CVak7Q~J<lfPG>
f=ebOoPhRa7qPs63Aj>EU5jW%b*1^08N!lPE9hGJ5m$KYGwW@!>MBBKWB<v*;?Xs=T;}W_j^3Ixi
RWaOZh+oo6>A`Z9+$qN*+zSrujJ<T6UJW%wPXC&kavhwt7!c>m$u(`Zr_b($C1BD%ROt1NnjgNn{
(B~*{|X|$7IpJ_C?gi<)pAO7>F?xeh$L&H@zJt?SY6<wCIDUK+O&hom8y=T*i7AAUK)|dF|GFxQO
-*PsM&a&uYNex6N%VB@88|5|3V>T;qXo4pNOzJAFqx@<<%dWDbhLUG@vPjY4a*;;yWRccc^?+Bi%
N42)v{YrYa~R0HT;R%{6t`KCr(adk$81q#vj?~7l~k&dPIQykm$YIqv1m#gw19<=W}j|hPif^N_$
NCVxmzA}X{yoV!0tVPm%Qk&(pmPjoMP$n?3d^YzV_e)HvOzD&hy0;%r3ov1+HouN_Cmf=kN^M9$5
o}+2L#2ID4b!Fco~67O)|@x4S%>O{-`y*m)FPXNx+Y04zL+hQqzxs9xl0aWR7j@r&$A)ffzShFD_
v;ch}Re_K|0otH%g`*xKPsKU}befj!%RKeh~PE?c(Q~+zxJ8tuNez9C+BQxu(EUn;4by5s^kG_f0
SqY_Xqj))o<sbAO4&>2YC+hcLto-d0O(!}_KVqW*9vAsF47V&YfS#fT(7!r6DF6fjtYB5r0znVD>
qQ@6iFjQm>0*&XrFpjK;tFK9@FIg&a~LYF2KI21<rkL-I8}L4;PUFVN&#NyWyPRJ`|>fHWp!CZF>
L{N@-T@2P^XLZCaUwRtQR2^T%FD6G@KNAUF6i`cryUjEGn`Lwnw+Q4IlHOfT94DmpL3+IC!|c))_
b{u=clf<Wm_Np^>OArztF8c1uuyz9_Gp!y-$W;Y!uCwSQaWb)6N_bvj#`xyo*1aRnlJvC3k0ho>3
N*^Dd9(i&Ilq>%HD)qeadzq?G~5T4IUIFq>k@EnTYWeXTQR09xCX;pX;iY&)<=_y2s1B7YgRMN!-
fwz9}OI4b;Wu-q>^<p`x&DXoiY6VU+etZA&yVr*wetdT{e*f}6kD`O9e>>RipA=7jc=PNp<L{3Sp
C7$buLeU{B!Kice=~*m`~5z)!{uKezB+mj&wphU(H})8TQ3V((0qEb)!~N&e0T`MNO5KL;~_r&kl
ogBF!aM6d`Rb7Kib7d?=RDN_6ERmkpm9U?;g@S0U!Nzk2*xW^D3*;DS*I_1yrq|_sk6I5te$kgbU
*8Sve~gA5u6N`t5$BjlViA{Dy0AQcPxm-|(Cx?#-t0(d{Ig<1~|zAWeABMehOb`(yv`Uco)i(ks*
V)4YC9kEBC}o*&*n?E+Q>WQuj*HKOzq76Hz2O?Z-TQ8|%va{!J#hl>zUP0s)!HVV(9@i;H?dOVKt
Zs|n0Bx;iQ51;n%AwUEE@!pi@=XehQ1bHv2{8KiDL00e%5K~O;Mqfw!cHfiBZ1Pb$E|ynR-tIg<c
Y4{@g`y{3FIFY|w@7om@%8?lY~gz0LM@gBBDMR|DBgx&aP8lpCMR3b{V2A&GQ;V39VLl90o;Mr<F
`h<x4U+f*dE;5Q-%29KEui<TZy;4ymGov^A>KS<;>rZ%lzDXr1#C5w0S$rsJv?4ya4PCXp>$)0j%
Io2Z{nLjS&)|vh;8tcib*jBd$IGI<JWLqpn@4Lk%Zx@vF4@2*u+;^!PE=O`y`iEklT2%>@DNSUP|
5B-%N}-&QZ)7VvWY6MCSY{>+Uf*c&aITbx&N`+!E`zM@6xhTbUX_1`(59a`;021vA!G5TOPUhY$I
1%5u<!3OQGg}3E?<b&LP6XIkXG+u)EB596huty`Yhta4v*b7wL8LqFmGi+AO0~N0o6qs6Go7Vt73
{3DA7wQ`JTpkRP2-p@NlbU_)?Y1tq+h>t@+kljV=_4)>e3Qi6nQMd`Do`{>+!)RIiX|gbp|>Qu1v
dEcIb3V%se1O3p4rQkB**<zyPtG=ofeZUG+!J4B<;}bv^L8xig8_z3!n?=6gI~1-X^h&_8%p%fdB
O<IEH@m#qQxM1Hy0yn0`^2i}<hE1bEH&`jvYhGnv@^$1*Kycss@7K<u2Q6%w7m<#vEMyiG64BAvl
DWb+P@?CC8~z<4FW!K*K;_17|!2aN@ze#Z+SIG1?Qa;csM5`TMeSmWDG3*K#7@Y5y*VKTrW!)X2f
6&~AbuX6YKRX%N61!&Sb<v}%8^y_HY>j%r<wUm#c0`QqTy*?5<@g98p`fFhR9)`R9)Yi<7T`@>+G
$G<1@rS~>M6?Xduq=xT&R;eiX+DTAU^rR-fX)ys;m=1B7}(AI16ksJuQ&W(1g70VFM1CRb>R?a%=
!HTZo~|Dm?#6%>W-u$QLNeHNqUvp?IDv*j51y~gc#H6?&>N7ehei-FpiWcvh8la_h>LkzKzOxR&+
%SGRx1ts_f>b<)nJ>;?28PhacYeuBNc)JIJd89ZWPZUUJJBGl)ol>0zD0%1o6^!D<c#5jZKR45t?
;X|-;!?DIuAT~4^=E8s=bNj*amimL7bb?n1@qG?(CAkb}N0odK@R_;Qr+%;PHw7Qi~p;kUMT7k_n
P%ijj+dTqbM|W=dPfqzyZuw78{*!Y#-T_u0csC(8vyBv=eUj{U+&*ueK5yMVZ=vd~(`QVbCefduh
fnk|Fo0Ve0GvIy<J-n<8&ly9uND9Kl-L~PUy+z>xjUZX9l@mQe6~bE(|LZIO}li~4D3<gn_du|NO
%^id+;KKO>JBn4oOYygG*8i!$Z9vNK*l{??IWzhfpz|%F1#I6uIa|OcJk|xvcpTjnXsV@1Q=Bt{b
9ETHMfap(Yb=bp8>!)|3jZ$2K>Iw2EHm=0s&-J+e?&pfd>!^F@6bC+)PN*~o2s>ui$oi;zT09*z<
o_zxEp@gzTtZD9dJ=rbiu9}K%l=XEbhMgbE>Suab}M^S9V?0jl~(&G=vXD3=TeTWlE^I0^Rl}HJ)
K(MOIc||ClMfbRrvn)j!Dx9J0CaM8uNJvRS5fTh?d&KLYOt&CeKt&WAkMLV67Ey0G$}U+>U6rhrk
dE`&ObM)e_O$u)<Z@YjL^|yFlpkORhVS-eCCp4~BDX22du)kLEFi$e3oILhv7!FQC@Lj#|0NOp*i
1*dOB#{@KzNM-IKYd&!ud3^oUT;$z!RCCvX-^*-i6Pz0R}Dfuj&XW42KCN2?K1Pb)>kDUJ5%^Oyj
s^T@o8B@j6|lw=sUyrD6GX@zBy>)3S+6+(87abg@Y9VylY3zbMLX+baOu#tLn;6I2UjYM*X<-boa
x$4EmIzCAUab|OpYn>e@Vv5aukT#r-ej5=MtE`oXJ#NoC0<+w6bNGRL`0Dd-REE1nB&(E`ki++xX
45b1iKn69+ei0kRIUt&>s26uk@2D@ddw9YNQ7zuh%5-Y@F@hQB6SthY<3~A<<ao3Ts{^l2wtoKb-
Mf=5R|JDc1&bxo<H!}yuf5``OBC&Mqc-^RP^fRO#Zx^pyW8Pz1VE_A`X?GIEvP-#X8)x7id;3Sb+
2Bg)tGpC)ZM57ar*-Mv%Icn*%;Y`v`{4;+9mR-g|*I(heHczx^H&mO{2%*-YHJl9SvR51HBqnr2|
J|84wW@@-Y<vZh*QdJ$i!P$1Ejm%3t^e93RsR-r*>|h}}neE$RAEGv?OS+H6~^VSV=T4OiOfw=Bj
`@x0{%rF;i)R(N|(wg_IFt)dzzF27LlkB!=6+-w=S3M1U+LNXRr*Q9q5+P%pYNbqc*uIU)Hk_Tu<
(8GIf%!r4;!bgL$nurN;0j%?cSW~ThdrPK?Mw|Ao1ll)9rrCifSPpe(w;t+xi2RA)y=gailUa*vU
e{%v&P2h(jel*8-INpjsLr3i(A3On0|!bi;<>2EdSwlP5Q`ZqCI?(JWL;hQ`e&Hvm`T`3zN5yT1X
qPmkgl0HcN%o^#V#`<B-L$(ie!|Ek}f&6l}CL4ygWKOiXJ^g9Z-=j?go2N_X#VWJK8j6u-8R7;*W
pD)~++}>VjFpW_6L3hRq;7)SpG!D~M9bw@|%aFm8=mU-cv!^b;yRc)?|^P{>(T$S~=qc3!;DXu`D
N;RumU<7mD%t&nsLrCi<NZnzETxwRQyw3Ds8I0ulxs%Cglm8Yi)6=|X2#%+eg4BMve1DN%2mxT^8
yjYJ3@b*I?Y_u@GW>xo?4_3^7d|s0`<xP=AQk+3^6z%K~o21ZXe47<z1x!pmxkQjh6ARQ0-_3wbK
|W`m-@?Q+gG6=vqi9y%M0>m`2o$8R6+5FCR&f|T|LMb^gA2NYA9v{EE`EHNbfU}rLgao!-G)E~Uk
V7d$f+Jg``x_g4)$PvH|d=EVjc@nJc|GY9&Z2_C1kLI)+@`wo){9`4i1O?PPE(^GS|)@FUe4aKc_
P|{3%;SkxCmMawjmSMS7LdBO$Tzdn6<s7CfJ&7ZpJ;E=zVbukWI2R@RBv(LUWs0UqxB3XcG9$8rB
uVBA>^`!$>rnVL+8dsxAXAuFbUWLH3POj?1l%#QxR#Az;_XuOKCbK4szg%?j8j%iuWVqTL!6V0J+
y@)75>xxH;k82T_snM_<5zAMKsmyNV-k`z{(VeNKDEn}JbSsH_^nN|rV&DWS6c@Y$J3xKlcUi}iE
$#~+sa=C=v@}$W7s<UzPPTNHSjJk@lP#JYKBW)zgtn6&(I<RHCJyif|Ndr9`gn11_HgfEe60>Nl2
P$BA<2P@Bro)vhlv9{NV#7-MHS5$FG&5EME{K7Bh(xMxW*Uwa7Yg?@Zl~#JToQFxTJ-TSTZr5-qt
ZQ`wmRP&3Ics<db{wVPVKuvET#@5yelR!F1qiLCk>PpsTt>c}WcI+#tk8OCV(SBjSELXr>8_FdNI
&K*dd+`$tTaisjY(4&^Sz+<`Y7WD~y^^B$hfDvps&AE@EO?BzSl<~p<>P?*M}0E~!2c!)=YIW}2}
X?-`(4!q*X$H8hi<SaG-zX6IXG){`U(Bm*U9(AJ8s5>~do=YQ4tQ-L5!}f5E`R)<Bhcj5UGZccxe
2lhn`yM=qc40RKS?EVLacq_WYJZKz&u;i{VBTnJhQ|;~P;nZR!xF-rkR!yBjrl@raM>W%E#Uw7nC
K`y0BXFe8?ib+O^l@D><)z*i?q1NV8k}DPH%6mw>J%$`}sN19jH=(Ic!7m#GQne0L?z~{v4CEf+Q
7G?6e_;!kq}npHjGf(gD-sF*FBQ9Hykc3{I0~6)|J-2zdDom4>5zY{Rfsfi}|F{1P$cG53GkEP>2
wKY9W$1EV%g0JVA?$B$q`a$KVnsh1o-3<!oE(Q@ZzwE=t|C4ue`MmOl_VOvKJ106j~PNC2-%y9Vd
VW7`RiChLQ+5Tv-=M`ufkXpFcK!UYyO@CEieb^rN{iHAZ4~2055uK{900D?&_q{!w46G_cx5`eqN
<O`9gBq;0y9R3Ju#9u;Rb4)lJ`~qq27d8$mepi=b$tBwT(+PS!RG;g4xbQ2_7eoVNeJwuQN?2&$H
;Qd`^O(~pXUSkOR%s*u<+5q!VUuhcAIR_s%nv1|2?g?z)ovNrjy|x8#=7B{P?A@*|~)icay*XsnG
43LWJO9U+0J(cX9N$;X=S$WC-*!$m19x5QqfYwIV@sWal(ol_X_&(8MwuPg~1S?4FM41010aKZ4V
vJ`Ld$HF>Q0$#_SP<I!o$Ku{QcrY8y%#@Vf&HHxCCai2Xu9w`!MM3?Moh$fN)`1>fM2SgA7DfI5U
r-zC&Spe6Sp4Y&)!6){&z`L8s9nGSlO-Anw7_r5&KudE}Uje=Fmb@-HO2MSq!g&fL!Xzzl50+KN#
=J;sabsfc%(~8R<t=o3mDOlM!Q5X(6fbWPi3#vifYtFi7LUAgsjm$PH(p<+a=up0eyy3DCb2b7^F
`%oQ%JMq6#)D_8lH-D>Ue-({1OAZMBgppa41y#Uq!cVK!ma8tU-lY_SHzw&`>R^i)tld{Zs35|NC
e%rXiIE>W>j+NZBDa!M`CQDNKrCX(Yn_n+DsI2E!HGoCa&BvQ|@Prmq$njOj0=rI_?;rM#HxQU!N
TH>S4~rS&f%wC1=UF|2bZp(fOqFF<P5%lRyeH>bA}-FdQU+Z$6|t!-~cc6r^cq`f|88nGe1lHWso
k$}vQ8bNGu7d<&>O1)OtBxs~qB2vWGS+e!}Nk0T?iwJ6^-)?cJ)Y%Hc4b>=lvCRIDqB7&(Ph}=8*
p>7gxJTO&U2D7T)M#3dQoQR?*DrT7^_{FVd~j*comIqVJK4G8Qk)}n&d}oa+xaY?<TX#f!$u4#3H
lLRmdgd-!I}`I_QY?RcVU_@GPGmG<zPo6w3(nqx4lmRqh^bFIZJEyR~4bFva6NO$SX3P-K2LFQm)
Ddce&_F0aPNOMgV=EtLWzP4qacF)RmP)t6(5*eUhCWnNyO7kJwBLePvPDOd}S(eWg~1TZ?feNR|l
%UM!jp95afi*?f#wLA=y)xJ2Z$F#W&j<p#a{#|dJk2Kv8-8deipNeVZpEP}gnJ1N^=O|Pt^;QntW
t2(V$#qXz<*0%XOsHD^XCPw~U#K@u(T>x5QE$Q!|ND$G)v2`G^+ODqFzkNZ+{L#OJjEME<(_~|6L
L^0DQi7DJZS(|(Xelit1lVti$AGGPWiNn>Al3*4s#slx-Z?AC$u?uBd8K_0#e=`xS#Kt*GXvOlTT
%<9EHW5fA#o5eRJUz0gaSw{({^o(JVZNE*GfZZt<6j^KF<mx61#?w6-EKWVj~Q)y=XPJSOUGH>@3
`+Q)ZN&fdvy;7|9}JfFQ;c(5-Dvp==lFnxz0QOkAa8S3yk%C@AmV-w8mF5hSoB29qc)b{OjA@3X>
S==xGN7~Gn+z`&ED>@JW9MKX}76Zs-TlyAo10v_PZDLhKSaKj+O(2}fLG6qStFtEHkJBT|~+pdi;
7sh?i1y;3fY&SME)$lDm8s-+h?MB161MN9zkoe3Ra-$~D6l}HOqDU^j0!b=BI*0~|W$jU=7?(yjB
Y!*5vJ+i*qR9+iyRKCX<FA1T%`nap$=joMv|w<41j{GlO*ueAO<Gt$zG8TehYGnOI$|27a8HQI`6
ETts*p><W^9kin?*XG19!#|vJg#u1&!ThXQY^b4~AvCf;KLxLv{`Ybil25)9F<C<dD^mw24jT3kt
-5%-%fDEY!rUl^D$ndxond`&flfKADIpjJr@DkF{masX7bh4O`=!t^!MG_%f~1x?Y&QI@ua4*h#G
JdKVem16uE3)jctU>0cKkX31FBG)CC5D#`J1o~Z+J+D>kUq#sgS9i>x!?`_@+!MU~8atKcu=smO%
nz>+lI7LWd@tsE&Fvps0MDHMkppokjiy=O4&}Nc(<33wi;8Xm%#F$upijzggmN$tl#JiLFm#y`$z
518Bz9*GzAIg%tjqYRLn{<6m-9Y(EO|EGIPA|^!T_?IV3zGtV-QNJO#tRHj_V8g3`noV5&(ufX?3
4_N19Z&?72E18t>H9QBNOy1R<7YX8W!7>BEcY$uw3h5n3E1eWQ!Um^QHFC=;<IH^73NUOZy4>Tq}
IQrdpA)Hunpv7-#Fs!8}66XffFJCpa!eGPajkJs>-P&dMRJDp)&P$7<iz6=d}`FIiz^L1^2o44Q>
oi}M7fWd>cEr~9jYKCp=gsu!*#R5dY_mg|SWrRDyC%;(q=zL?=SuFIF?xR6hS+rttBAR8K6C~+U`
01RrOS8TT^+hIm)3N5cUYo+x_w1bT6d(i@b&Ao4Lu&rz$JWFCnMlf!;WmPZH;2MY~j6iq?_x~beD
KV3?XaP}?Z?nQW=nh;sVIXLOwdDgvV^F3Gf{I|Q1PhKB8sBHrye=1R7>Mc$NEj$Y5h*J+im(s>43
q&bE$%p4XDuRVSfbhNF8XCzeC#<+D;|6RbMf%u4jl^zB&_Ee3gFp#@0OIU`zbz0<CJLK+U-1>)Fe
QScZMi9KyL-z5qXBQghKu~Q?Q}#PY1fO^}h8CRaEc(G@6zfYih1&%=bA6VywqTvC~!)Bln}&8cat
oRYwmhae(a=u%_tQ58E>Vt`;sZG~7q)T{hvTQ=XyG4f=Efyl9OGx!wU23`K39_<J1YRbMqZg)SKp
tQkQFz+8tO{rK020>F_k0#n4Sx^M!mU>`f&F!`A5_M*4ez<}oyh^EK@q5)AfsA=g+CTpX^07|qln
=hD~<I1!m7N+i|E8hdONFxVPNHLA@VCoO{;($&KHdVsOtt>`<B&)_E_(+0J?d^uzP)nxNz`&7y%+
XmKLp#<w@FaZ6>ERsV#CkKr8Er&CpKS5GunvF1hHw)21pofFnL^x5X)xR;gp7(Yi6Q#AQ@o~tRI6
u*<mG2ikt$ge#P9wD+b#<$c3?S4XKU_6lt5U;072P^byFn8m9O%OkduQvtvE-1{I1xJK2lJ~S1jc
QYKf~(v@_IkR7jX=ML|^3rC=?qAcy2#Urz8tdqJ0+@Ug}6+JEv3h92`DN;qKeDfhhw0omKrz(C0Q
$a+fz6%S~5mBa6ltK@-&-;?V-E@Sxhz32sLx^<url4-E}I?t>Zz2Yd%Qx24h@{Wi5J1R!G69kG|+
}Ry=c6W!GgkhlyD~n0Wi)fz}-N2f0L}4`Hyj)}o)%#6~{~A|f%1K#j^0lSOp>qsvjXj`z=wgxG0n
MJy(ngDm4AuW6#-&*5@4kB)#c(`Oo;BP-)m#4|Q0@CkFM3&v&YPlHW31%Hl*`FvwnWR)2P%3oV4y
1?GH^)0WNA@-6;0E{M-*>q%C5qYs!W&VMUgdzSW!SCj{04~uW}~Qm{m(CbBEpN0=cH5gQpUQvi2K
8XGkDDQE`u}^Aq_=UgeWTiBcIASGvOWEhH*?dR9uisL1Fwl&A>y3d0Jl2#oniFKe8dz!_15O-OYH
6oclCfT+m}ic;nUlV&d}3IfHk14k-gO{hVnRoI+??K6Nx2iga1B1C3)MIp=vdk>IGeHc~$SZ3KLT
XyHRcXJ8*L!v_lsAbge4F<hlzc<{)<<00^Md#_nC{7j_e_w~faR`F7w7~V+61eQz*30#kUZTFld2
*fjy9QWM)y9^*w}eO4`*{mi!82$FRHs{8M^&eQ?T8O>6}&ZI1guBT&U$@Cuy@3JZ{L3~*z=zZchw
VreliZzM||USk{BtHyxMQRT1_KJJu|9io7VWWs47{{Tw1gMlHTj-1-lr=5pY?wucMu{R0H#sD~JZ
}!ip;vypIQaZWRI!Kn{Lwg-d)iVNJv~6j;AdA~-QLp{E4V0urR%^p}RNM4@jiMTekK0uBySyv<jd
G9?07eQ6Y9=*KersZl^+my}3yoctn!ps|R2Y!s2z$0G94D)O6NynE3hIcd}s9TV;y3{%<hL|o{Pp
EDmBs~F%$Q%bC>YR%UMD@9tav>-%Ud{t>Qd6iw23l%L=9<C68IRmqA6O0(J89DBjab-ag^@2z1jB
s^5cQxFyVlbc`!Nmu>0sK2VJ{D8Up}=}&Oohaek6=jtNJr)$wT22)BF@YXwk1!F`=`g6a}q_5{^n
R@aQQD52!xWWq!WPI%E<Lm;4v0Zj!Dgo{y?sPpOP04MT5~m&`yBsiQFtNbdnsVTR9-nG^-|ye9k#
A$OzOC_0#Qs5S3LAJM2yK1$Gdt@99~Ef2|=|W_1(H0y0f&GAGeh@ZiVTEOL|*!IdR+JxX)2)oyv^
G_h_-<MDY8*T6VQT08P0qpKFO+q|l)SP$Q)+sNt^1JIfx*adOkS;4Vl4**-%=iPl&Bm%W{9<p|tm
J?W797_)a(8TAL-Vxx@qK2`Yh<=hEky$}GN&JxYtca%wBF7lp1fw0C0uE$v5D9yOyO9+@GGi{Gm>
WbTx49hO-&J*Xb#$9kgp@LBE?$I4B@(QLoBu6(vB87Mm@=1Oo*+s`A@Y5OW1QufK!reZGeFizm*V
eqIL`}q`ycP$ymouMS>&~+s`_vE{XYkO8BZNVzy8)_r!?ep1A);{?PCx25o^clndmoA0k0m>g|&4
WK1kH!zvEm`17l@aEs)qzvS*x%+CnsHz;hu+KvcpG0E*F2k$xy>(F$EgRfLVYfqRoIP73wq^w{yi
3e1&rdfi{Be%0)H5t_D8YBrRH+^;xaN+FR|@P7t&8klCp>=R8E#JF>Xu|qNdYOMwU=vfFF&o6sbm
VJyH@k?bF;XM=F9KK820+!?De1Q~ZJnuxy`4}VbyLjj=<&(plUrZDI++EHc@7*&_^;KO8%bqUl%M
#^DKS9Y3lusv%vI5rNKf6<)MJ`8n&M?eCMlFcFjARTG;e?$w%*_}U#p&XT)I%LoSx`zW*4JYyF=f
g}`NVqBQ_dwOTz@yOFe8;1AX3sY6x1NCfYw6+^Bm~>u0w&tO@tO%EL01eY~8v6BgJL`O&y?G60Y+
pSO+UWZ?5HMECaB1j<Ec=Jo_bPzz_mVZ{h(Bs-wA(0~A-gJNvivI)i%zsQWih|HA~ouQcs%OJh1F
b6m%gz$-vNd(prD{ks19-^qJLQjDR|B+EuS>cCWN#K#0{iTWXcEW-@QQt@eJHxv<P(=*QTM#Ld1k
ji<N^2(F|!kD=)|CmM3cb*d%z?`6rDAmilF0ZI8^?Hr9&u1LNSPLliq*0Ex<nUc|HlmyKE?S@>HU
JwK;>YGzDAF1)kF~v2N)hqEDAu!Cex^``Dz7|AIC}WNa?K$1VqOFYb&&}k@T+5o&pmDJzZ9#6`%@
YK*GXE7FRKhjyrvEgR0FCW?6J*KpL#czIad}U(rp-o<fRgF2X`Ia@9mwNUyOZKBTme9x`t_3auE|
RPX=(d^pZ101P(!)$`Ux0dP&-HwvDV9w(S-<L^k2{3T>0qnW$1NcQBHt!2<;k%EH{XrcmTT-(7gk
<T%r_<PkE-W;AN9DHT|amN0_S3NsO;TIF(8Dx?v$M(I>isx%r(z**Y!&Tt5x0J($arf7CeM2zZ_B
Hro&JSMYPDj~UxgbeCaIc}Yw_fcrq?=@UyePFA7KwFZDUDS=P?W*h*q)vdA#CR$s%Qd~<p|L_e3>
`k~L_0pgdXJFob?swSgG_BKrctO$Y?<Bq&2f<~V#mv9&_%eOcKDkJK_vSnqaS?liE&dh?wim|DZ)
Pt|2RMGIA77ltNCcybOLW7X}ul5jC2p~Pwn5l5il4Y4-N@_HuT00G|xY})ibX#o(V_Z4dA$>Nxm`
VcC#sK0mK?z?=YMbOpM9YBMlV2sN`vb7yuOQ69ZT2e2hpWaQhz`G=l&oR!2}+D5W5tBNd{61AvdY
|Ns7X)fH0!HYg$o$7(R3rQxbCZwlo-0ynFn7V7d_GWixkATh1v35|Mp5*(&;AQxt{3Wfl+l~J_{e
QSvnnOInVS+BWVJ=iF+o5nR5x^~+y(!ZpLW9VP=gClMCD<WOHugZHLR#vQjXOB}vYimp8v)S?rNR
=(eNNHnRA7yUTYnYcef@b{hcFUP@I(2k&$=VB!C`CRrqm`EqmI46K)FRihg}t-<+`xWo@PKf$N}7
DXKb-caQ|?3_wr{+i;J*vc{V}1khC57ophe33a7+(%9PW@;U>f-;bDd1kkCKs%;3k)4Sy3USMptO
^hxCqE)+=puQHZA+=VA~hN$g2k2rlf2<an7b$&tXK33rB`W9ahgj7+JU<1n>`yJB>q!I{i6tRo7y
2c?gv_zDs|fno$pzW1P>Jn~|P$68K_mOc_jfE73Dn|P(#7B{GHx{bb3BSf+ouP7eZNQR0Q9l(+@w
auLTf{iA~)?vli1RW{+mqX4=Eda8}<`g$UlF3tFE84=u-_^IUG#8khE~9AF6heXrInB|~79Yz{9m
&aXpEYIk8Sucku9*T*O5!8I({QZAU87SQiN_Ia1_@laJ@hN=*q5eS*p7xEdvi%rV}UFQWV(4#wYw
$iIQ5UC!Elw!hE`UGJpvIsNLv`1hB9mFBsy#)yxad~Z&eQ@ayn409Pg_19ymk)de?d%<%sSyO!vt
FHOMMz%)va;p8yN(HzW3QHC%|@(aH=wG#+h%z#j8l`FOO0(Jkc*d{(|j#?9X>OCNgTrFndSIgdG`
6A+&;>I6N>hr5){hE@IFc##{t1qd49FefDIK&`1I_-5pOh0oud2166L@r;<y8kw0H2T2+ME3V1V8
BM+`)>G4mj;r35<}C-rD<Jn`lWKfXkpM*Hi|-vSE|!?y<1M|3E#2OMLFk1_0!~R8HJV}>FG+Rv4a
Yt7(&==ZO49(y-7c0wU|wYZSmq0{gG4{d*&I4Lq~=MBgCf*kT~5}vNWEi|=|qOhYpV0JhyF=_sn!
<(;_hAaOhU()aT?OgSJ~nsQv!%&?Rd(wUpRg`^+0zu6XLjLh-%ihu$)seS5kFk=jn1*E5RgOPRKA
F#Pa=Q>yH0?TBSVF(`AD;z9CVhnv=*5k3=qV=-c)4<5Wq`f)n~41Ln%Cna}d7Ztxnavh)EBSA>(O
EBb?-RmMt12}OJbAeN%!!zx-eN_`lh0eR52B2{~`rFK-y5$21WW^#Y3v`lc!87zT@BY6V$V3M)}^
E3{77?DB+^&!}~Z3r+c(Z<wP&gk*F${EYNSPcucA>v1G>qH25LA#Dk8ZW2hPSHuMu#|&;sdGt`*H
n<HBqxn5R{F{z<{?zw9=M8rdB3{@WOsMCS8<C6FdJ&~Kuzla*}yhny&vhUE1a_I_2H|d_rxfu=O<
fl@Xkh%4-MMBcN53lN$hiB6VI57H4`I?4is?#=d$D8UgWDnHG}qGzH09k2`zaopm||HWVf3}*FfV
`P0{4IBR|#-1jpbo<F*&4$>XNiBCvTpinVeXhkC;Sdo_%#jw9KGf;#F$r0zWW8aM%wxJ8pl>B_8T
TqSfg)bKj^MJrgE5CxEgW8`H6P+`k78ovPxbvgiRTgzh<Me1e8o<WD}G$rk73O9?gCS0hh3qO`)j
#UJO@t7Iu@fh#r@mQ<1_?kW`pzap1lMBGHV<a~LdECLhzIE?U50=&9!C78B$cpP|P9cAHkmaLXbz
DR7LO-3Ax6#gCUtQbO5Njk;^kGY9<;5~n**UuSngmZwaX(8Ji=1r1DL#O--Q_#_C6w)65Bn5`xGv
#%UQ*Un;A=^YbyE^FW)!1sN$g`@Q&g@>8CK(cqr_Ne8TC<LVxCN*Jdn#{?qsnndePscAmZv7tkFq
v`2N|;mso1PT%aOzWQko#dS>DZR4SzmfB+Q8uV{Whm&<5cN_c?T46VS~Bw3O8bR}B0?#NS}Gsn@@
x(D6qNkP5N5$ls(e7CzO%UaDgSFu}|V^I;DtDG;OF71LcGe@y2jPZ3DJuhzx${&c9+|l!_`Up%8e
=a9<DObJdt=OdVp!Hfx7bK!tqOO*veTa6QKqpQpR~vbo@t72o%1krgv%R{yj$(_wo)I%Xl1uEQcz
m(Ur%!rk7_22ngZc*~PQsN@?cvMlK_s`b1!TZQRylbm>xU;rI;%>IJ@c`Wtg0p`p->^{7FVg|MFO
qL(ghmomsc5YATA$8#7IvHihhlSKIU^^EvrdMq626L$j=!E#yBi^1TsQglfR>+;_rrb=|xWoqwlD
VB(%bOB4J)y9kEd<SmeuBK!s^)yA*yzpCyMZ>R4c>oKZ>M%ako~f{H^%XpswxjzKSaZ)cOuD=p>-
k_MK;y~(@A<J|FGsn=X4*bhVY9lDoP9U~DRSty!3B9#-mvZz&BJfjppDa19Cn(2!AT3n7Oa)`2!7
u{_x+171-oRhHAj{aDs7fO=HI5P6FX_NH02OtP7l5C02VMkSh9#*&Yn9oqRTyznPpP+xd3MwgwZD
oA{=I5gm_=n;u_X)a0<FwwewWUl9cnvuC&tJaN*A~N3$@f<j3->Tm{bkcc*F5{hy`C#oiv(CiimT
ff&f#O|>B)n~c+`=<QH>O{yXfWfe<F!S=Ciz5^q6enDYz$MP6_;_*eaCQ=%LK=D>&V+wZ_><ab7b
<Qw58%ODIMgk#Sbw5(DAkb5)KPPA`j~2fAAX)mdR~D7P7}Q$#FFXo$$Wb*K44S~cg@z2l;b(pvQ9
okoY|Z)9pHTgdCGuVS_YBUxaPDM<^SD_n<>Fsc+ary~cv6J2D0_iANnZEe&X7T<PGn&V|oOgkfLT
?i2+Fj!~+hHvm$qcIm==$>a*7iNUCFABrzCGakN!oz%xF%)$GY4RDs^+(Tq^vzONohq}dp1?gyRw
L0n77<jE*C5*I?Qi#@*NE@(#k30*>pNoH;HcB7*ZJ%vN0bt7=m(c+bvet=^mj6bRA0(Ue_WU<)#b
9zXXY!3=gikTQ|S}6d{Vr8{ru=B%82S;q&T>jAC6v)kAC`a^!okFH?QBLk>SY}-jHJRCen-qW%q~
Xj-WtJInh|?ZU@k3Nz!ru3MTesIlhf<Zr@^HS2}grmRcuNPk;C0%jdj>Kt@nTOiloSaerr8DNf9-
q>VVk(6~!DGic27?9J;Bhc90ry&Jze{O;v5ieaiU0CzA292AJ;;}0+YdL$p;zI^wdCiea>FW-*gA
mQYHMV4urjTMndi!dI~?<VL4hIBEl%0*uDr)yvwl%ujnYE4Pc$=3h#?&#Ui&we=SJ$?C_i!+}V{k
5E7xQUkqM?k_P^jp836t50{8b3dJ`{8>S)Q)3yjAuVqM93JBKtM12QUH!fW2(`^JR^#_)!~2<10j
)Uk!Xw=evjp`G4mA>vNFl_EUWCX+ZLa?xMIlcg3UHDZ$QwJS?vk>&%q;0K0>q?rX|;{IFX0zOKX<
Kp1QtFRv9NdV^HcdcjY|;XSxLLq#B@pATH2!#Oo>S4MSsS>~0_&Dobix%ZO_U1Ip22foHbDry<vV
HP(4KkNZhmzI)fs)>!}+JfLu7Moa}BV4g)bWn<e79QlEN=H-P^YJqg4=fa#hZw%yl%J{x<69RT$7
8Z+w(H{A3N+Wx4XlISaVGJ$R64}NodPYRihqA;-d<19252#zZ_l5MIqyyC~gNd0+_xl*Bj4Jl5Ls
^w1iFt57ohDyr()S3jC=`o2e#n$q*ns+p`0xRnJ-M02%E|9u^fAlW=8~;BG3rN5nEk)7Ip`WlKDu
tF3!ti|OL6e7L~qY(yYgH$m*RDdnzwX@l+7JcM0h*Pod7lPB<K(>B=0aLsx_+b>YH3qyH%DIp2(D
DiVPFZ%GN63^CmXH$4NsPr%L4&>^7Gf`L5W07+@6i6n8QA10B&_Dg){P@v^8ZT)3EDY-1l)HfL`$
enu8`S+Tw=ETw(V%mh@D;4CYQS|+c?`jU^E4lNX@@tg=W=CSFnzvElv<`PLZ7LuHskOgE<ZgH-jT
2d`u1+ah?3*77R;MBJ8_sEo{UJ(Z-Hb)N5Y+5#G+xts^xtVWXA<gkSHn-oU5qMOF$|y}(^v!$1pv
_TH1WjjgnedF6?(eYR!E%XUVhwQ*zF0L)h2Q~(oIP`{Bh?K_dlN@Tz&)F>A*(5)s|ZRw7lI=aQwY
BTNK}MIj17plMEOd^98xcOiilPWvr*JBNB+gxdPc>YoyI?K&QKdUCZC12<J<#yg*zaY6V@XUzWU~
h!6(ZFqN5I`m8fL*$b7Tv-K4XR!69MM;}N>=RCM3PQ)-IDH27}K&8N~U*f;?wP=aAtzo~L$(NwH=
KdY(B&{s|t?MU@<HS_yWOHU3WO`C>1sq}1*o5rCA{`EpS2f$S%Ak(EnS8(xUlm3=P{*Ptm0hXfts
8tuR=#?xY*Y$0b>7kCJV5l@Xg8cqVUGR9vbGQ+5*|Nf6vZ9espnEp+DY+NoO?pwHi#J*TPw6k6e5
Pc4_D`F!ybz<RF2F##Aou49awSD&ETV`>V;ddm<_;rxBk$jl7<bzLM?WJ!t>_uGB_eoa%f(V2Tl}
hO+!sbbEw*V|xPi<YTvv;04Dk685wA6z98Gv8(iPe5s0RMdbRa5SF{atym3(stEx3w`+?Te`GxB1
>BQ<z1q&FP=0+sJp@CzG*c^rd-aS4&DV6EbJZ~OrRw^G>N4xZu7f}TJa4JSn*dHC`|C`YS11mob%
hVls<0~S(PKw0PU<x5}dhSj4s9fJBHdztn$2M9PF+#nAiS;bygl<tT>4fLm>{^Tb#2y;Vb|5f%{>
d%Q`p)Uj2%`w8K%8e|88u(m|T<jDZ!@t{C&sjG680Stto8GD9{vCC@;1Q{5u4GhYj7{|zn;hq!ap
Q-;iG)4A=8I{?Idd*!j(vzi_8xtV0UrNXeBAGTlXlM!yDv_E-Ty7=B0Q==I76qP#ca*HD3|kikkA
H*9~HDr{uylhW!Y`cvPm8DjSwI<B$8#R<+y~!j0Agxn)y!DhV_J@cBW}gq9u<oR0Uo}-gp!kb5Pa
>t*Rd2wMjw|sckIctW`QzJJ@O6+K!G;hifg3om$G_Rl)}@u5gc^{73g4HxDFHxI&&-ca8MlBbqKw
LI!8KWgDk^Xm+qB2v2YtYT40<m?e^qtx5CL_+~INA!r=gMkE>4?leiub{bj@hiT}I=*^BL#S8$AZ
}{ykBe&o~2tIYeqkTzNjDHQvVLQ9COwnnf!+D5juuFGMI*~ZYXt0ZN69HMc;AXSv0<ciDtlAj9*7
GKVJJ}i#dDwC7k5u)GtVa79RsRp35Z&kfsWwZn=rCo9)jS-DXD_?FiU$r9Ho-5L_-IoAbT?3smkD
VaC!1z|F>+LsfZX8Uc%Mm$4zm<3x{5bUQ3(s%zJue{*}gu@ic-(Le)C~`_}9Y^hwn%^!M7~S<cyj
@OLpW@#MT}WntK3YS=6k5pJiwkjpnauLBf$9D_%%zQ5d@u(K-O1!{F+UbgFC{$XbH+?(aXmcu#AK
b{C|%_>k8#GS3zOQIUJJSp`#<qVQl#4Y;PM)+p-rU}$uc!4hEOj?!YCrUJ`9fBF9H4~IXK9U2;H-
R=$sBrF>YIpQcsc<SHo_Z30?<A)dB!QRs&Cg*7=(%6TWAAUG8O%3+G8L;FnR9)(Pe{}f#2sh1dVV
i0hWCAqoVDBu$d~ZGmdHv%LT@1fSF1b_PgM@}m*$K?Mx~Il04c2<b?g-n_Ks-dT7ZxL?H^=a5#IJ
{^7)$L8N!#0gpMTjt`&8;cB_)z$g-u}n(;l0C#Y~W6CL)QuYpC%alhT$bMWAe4<3fjoXlfI5^a+H
?>ax5cpkl}|8B`ECn8T&YJB#zjWL^{y@xYOJSsR^fChBt1m0*j<quo<2oX~*2G8<C4Fp;~WxB=}Q
AL6`w9H9VvCUbgeh+)#3Fl`LXSOF*vmn)2%dZ$fRi0Y176)rU&uEzWnY>cb=yc*+$0K}~%|6+HMC
XC2Vf5l3=s>7i&fw?W07nfvu!(N#rT2oFZ2g=S&NzuuE0yWLzo)iy7fQ#BddIDGn$aQ*(Smy!ao2
0iQsTJUyet*?YGEUS90YW|`Ppphm{o9>g%ZWr{C&YFu+Z+WR12O&=ed3}>uMp<idGw7QDm~ne_M<
0e)W6@?<$E(uX?VvBm6@tW>PX5>C8ZyZ)ObRfB!&DGGHRi{X8;$sFR_~Yxj^~2Jda8BZch{S_13n
NVc%JHj>!xpuiB$NCm<Emtdw&U=;4rgnB5+Uc}T<0?rCI^RF$x9*_;CpD=)8F9M<M{y=F>S_95p1
n-32jz?=^cG0lyf2lzy*&{q?dQ{!YqO<J9Vn%Ol_fEpcGYsR}Ljxlzu>dR&EQKcB8Y9p?^EhB2W6
HygD8(1K$RdAhQ)pX$Yq1u{-$!CtRC@?qdQK~1ra&Ue|E=zGovK}g<y`r$(i2Vuh=1k;~9npXix~
Yf^{oA4KIz^VkGt!}{#BU~JodwOhoRGov8DV<3zlmPVwB5kms(hI5xu=as-7)L=jMQkXi#@F-dG2
587Syc8VbnAuF_-OE0OuhGy|gbzP-obdUsl$V`Y$EV#}h`q{U(G37*Y1GYaA5?QgmuHM8z(aC741
$_8H#PJwfVNU}Jt%bL@Xx4w1?X+BiN0>>M#mht?zqwh<2K)a7>gWC&ek(OWre3GpGZqfRh4sclWm
7O$F)>JTeH*+Fe;Y(gOla+d}rg(Rgb`PB|V#)fcB?V5FdZ&Jahk%~cPY^>NV=XxkI4wt4e6{YhqX
5nR&BF9|m^t4qZ($KniLDhOd`?9JjYz>yI8if`9EJy+o1w=&yxxG}ZL{=T2vnd%dVS2xu%!102f%
&WnFoK0=uMnbLunmIC&!<rVE{K^u@Ca8Szi@{KooMJt-vptrp#2)h-q-(z&p3nhLGuK-b_U9fT!j
?iG^Y5J768ZWTFm|Y;k$P(DEhl>&CaZd{)h=aO(|7R-rA6`I2)6wtd`{<d=j!@!LvywhDJ7UmR;m
UK~eB)!L<ms8bI6tcSK~Ml9mj5E39K2&Ly@lNinQ^Kp)Y~vZ!?C0+R)|vi!Quh`M5#A>{fzosz>r
mrNiy$l0>)MSsgNg;cFWqyTS);_XbV$Hf`8%1BREYG)BnZLlamX5u6kP)P|Z7a&}A`fh4eW|SUBL
rU(X88+sX85CAh_-Qq!xXkDQfy^T|!1aYkr;tV@+EJIA<_sU6vO?fw>ny*}=X5Ima`;=Z4pe-IcO
-w>Id#b9c!1v2QWHP!vjz`8nr86%N(Mj$nARQcQD`Z5jx^$d)4i&<o=&HdF~unkjD%mnCh37->ML
Y*V&{o!(Pgi=ZM6uT#a&O{WizabtJXt!;Dbm34|lQCZ&{V$USbPr?CfhSsnJZeJ@Ur~LH5iczI~?
Ls&CWaQwBnh(4v-(N3t@f9R|t7k5bW6PpXZ~!s<m0G^Hr+RZZDVj9T_9&~#nal)p#C2B5CYYqd59
_Tn`48?;1X`zKAQZ`9!GAPD)n*+U*rn70m8HREF_qUwn&fOBC+D<`HL;B5+>DM$o#70@MWiJPP|4
v>L|I<^j34y5e6gl<hFM6p7_3Q;I&i}~^dpr;sCo&{5wutJ3T>u>h52rb^Ak94A_@*@%kAI%IXEJ
XPJHI^1Z@=C46Txg6YHOzP3+t=SUh+!uJ4*6c#^G#K<@*WzC#Vk|Z{{|X5Ia#0~!O86)RpEXV?Lp
R!-N7n!!w}#!{PO7abMjZMO;c2CU0d=%F&!)e-aqxI&uWqufyH^I!(@vmex2fFs{>0IfgFWDV=cN
xWEgQArH?$zD4uZ6E-jX;9KJk9|2)9!q({RTyOJPCmfCp!S&kJIT%_c}#GpyS8z3!G<%)5W-u0sI
@mLcThLS&S&ZC^j3hG<2o}t8&Xt!Hg1QAg}M2Lif$ut3h35LYA>~n<mDdjZj4pfpE`29HA+jW%GO
P0kCeB{ui6I0I$H!FO`h`a!8IIxaf+xW3v%t9HE<twT^fLTN%rZ`73gX}O*z|<jTg>tzS3}$WCx0
yq{#rpHuWvh-cIztpI?P%hMXRy$XXZ-1~f!5(5l{>2~j0uIY`3UmW7_kp)NJe#KaXulInDty-?NE
ikQpVg9a_E*ggV+Rm;ELZD>*JUbC-NI{q*_#Ee#Hx}I%BVvkwCEJ(qi<Z9S(wJIZiL<QCGm!@=#*
<mm-GJ*SCY^l7u>yYjSdA1DJ4LcsD$p?4JrQ&dXwMl^GMx>m&W!LH@DQScF{-s}wOBRP4REzR0Gt
qpa+a5kyZEDc&Jg)*ptvOjc)YF_tz>D-7-}km#hTTne+jPE=Xx$*-hQxo4oqor~0NGj|)`_?XNVO
ilvwFZYZRthbLNOPMwb8*Q|hlC4^m_G%cqkxvH0rxzs*&A~<y$q-+>c((J+qhYVtV~>}rZbpQ=C#
M!_Ql0bjNf#@1p%xtkbj7C73Cz_3Uagw>(#X{<U<$*#aNIxbiR=|a`mnGGRjUrXHcXMpwj3K4363
&ATG`e{DMP&@6>Koscte!B(bWqZ5cyp?MjVC0fD+TiVhk+0sN;*@((`Q0lZ&Y(pHBW8+==B))y0A
e8xdl;0`@{VMKQj1bkLYDf-DHD<ypM=>iF@K(aF{W^o;uF|M;2|?_H!2&riQn_HDc{aD1##lwLDP
V^-U|=wup!@0HFS9+?PVYH{HG@n|0*$}6PvC19`9F~Dj}aU8|dzj?bYmc>`fMVn>3Q|mI|K;P#6(
<}oA@3RF^Z=`6)zIll9nzA8^zNOIkg`amlijxcmI!d%+MU(uh5<Bbn5|W(Fm$WAq#bv<DalTYn8W
5Y=BwbcnBTBCdfWb3@OO0%}C{jmDL_xKBNZkb}b1mo6*P0D~QW?*`L|)BV4dMZXB8zw{+B*Rz@gl
2zl)vsGh3c4^MlQC7A(<-1jZ-YyPz$Su<=iWd2^`*s(r_S>Qox4H>&m1MK)>+bRe7Dc)?)<XWIEP
ySA~03W@T=RP;hajdb2~+HllAk{bE-#nazww^a`oNOO-8p6cFmzc<aV1$Way(r-eF`^L)Z--_kqe
n-JvD{26J(CPk{*pDQBGDR=|?QxOSz(GNtGGK4q*gUWMss7?ztUx_$zuF*q>PhzS=%Sc26H!O})8
3oQ+D?QlsL^%$+BAjgTgtk1BS`4euh|;&B1*u@M3lxrHd=4|NVhPmJ#G)!51e!)(rHec5g|2f6ns
5`2cZJUHOrL^bzS*~jUWap4D2oz`#DZ;^*&b6ekoXE|!efk^b;_+#NGIwWPRuUG_vCWv?aFdqRsf
D?Xabh<+fy%$rsY@6%pk_fqzIJuE0vcI-svD`u+mN$JLM&LYskp#GFEJ|5gDqk3YivMZ?`?p1tED
dZ)0k1d7ZTH)biTiCd%7^0aR5`$-XySov~2bH@3B##t>ge>unZPJXz69c$M0wqyx;;q>e*z=YuVt
c5FKwGJd6OPMzouI9OnLvy4J_q5J{`jeQ-8h!jGk@Iu<Wz#LbD-d@iEFFG6)xs^UiUskME4DcbLm
pHE|3t{NsHxd$9;RYokQ+ZQ#bbJp_6m_#mIe`zIG8GeyWLAJS6hakph64FWcqk!|e)!LyqRC}S5;
5(As>7Rhbz*6)bEo)e5;KdO#6`JgjY;GZ#NB8yjjkZl0=QPnVj`ilXaLZt2~3rR(hPZY045ZN&7$
}OR!A!=D3%)miwas{u&4p|rlle}Bk&q4O$x-&$d?dMdBX-At8faOKh*dktG5UvZST(E>cjNiIfe{
AB~w!heA5HKAILO%m)Y$!zko|x%O|8ZO_uA0E}ZrhrkquS;H%A*U5oiy34n0$bM)c6cMn`J?L@yU
rxzIt+QjaXL`)4gs(+F1d8}3PoyZrqex?gL9q}=F`Bt;CmY|o7OIztmuna}`fl?UJ4C-|y$hyuvf
+7_wQ$#|!kQ$1T-;ws=i>G{0*4?XeJp^?s40q~65+oR;c-T#T$r1ZaCKD%TGR4wElPpU8LrY9LKZ
`D9EUE;gn8&P)2K&yosM!9gm#mrXH~~nX|MWp9DN5eV@>!~)wo`AR@L`;Vk8{4OTy1X<=MwINK8?
wOC?rUeL6{qpz>pP{kar!j;#U#tuhO}sikp;GjRB7+ScD480S9erM$<(|;9wG0aEa!?!QNrIq!j6
w8eVJnM)CIGH3U*#1_-xEbaXYZ?|7j^<$&RpDt0ho<3G#2<YQ6Z5Iv7^N$@^eq!iLu<_oh_RBMV_
oV54|rRyNI-i&InA~}sdh!nRybTmDqy;)fYli%8h$`DR+rjlkZ6>37tXSh^S*nZAShA)(Wt$#Zhq
NU?thkoyFE(5#Cr-%YCDQu#$$CQ5P9mQ+1pK{TVH!_Zf>X3aYnKe+W^384p@6x6r(+W{tPy)QTI7
{t|dTR8vD*Y;VblPzzy0Ng)*bp3>bwB;Q>eWp;KXCRHNcyx;xG?PD+?HFseTkgF48H>Lig*DT3Ia
{Nn<KRnW+z9RtcscbD6k-Shr(vyOZ>a0B}ROTCGxf^SyLGgqDp5VNA!Ru`I~2yitAxX7bO!9VV-!
!9pPNDCS)qW*9;I5hAQPtgrQpB4S&I1)5=B7IY)n^>@E^GmeXG%#jnV2gM~TjReEQ_D-a4bBbZ2>
<<w+Gq)2>-Mmyq-G(|Vx8&;Cx-rzey=4jM{p^H<ABW%UCoMq`X+3RV&IFVh;0z*w9p%o&U8HI0*Q
NJ9Pq>kGF{j)&W$ERy*3qD4EtenLmOueoJeFlSQc6D8IT7%el-Kk+eUF*cTm>8G(j3m3>F{0JBS<
cEuvUy0h!~p9gw#!|rW2C<+x>bM!jfk|pLr4eT)GG!Z)>h~ty=#^cN{dlXQ+J~RN%T+cwDS!^p@w
s%;cMU(+f7xB1`MUBR!k^HJn?sU9N|ts9QGZXmaBB}kxWKrGxSg7nBjEfu_eVLlXnru7iMFx0cKO
OjB1s_e(E$pVc#(z^L$Cknydzf7(uFL5o<cZD~i%u+FA>wSucv5&1;ZICBtTIm<Vuii8P(bQb!c)
1yX#=f<mH&RrRp-xNsOwMR}DzhJ|b8tZX~Z6&_@iDPoXFN(WwOPxQKo*3}=n^=+jV-W6lur{`JBv
4UHGBGuUpBwHEsyufSD8rjhtFrdOZiU{Tqlg!R?swD3Pk@&U<s4KE^hC?g*4KS5U%&R3A26ITLL9
S91)pk{=SBj-bcNTCL1(mqCRDOFV^ILR7u_ehvGOyWITIDo~eyk`<+w4wXoZ3<yIhc+gXvlVQBMl
g-#xRcz4K$n0RDMkiYLw2ytbhO$4R0m%<g$IoI<3-a^u)D|YF0w`K9y)na2^Z7OPvz0-$#)>9z{D
j8JjYy;3}%IDZ!W6wdmEs3!9?6<5`t7dH9jzF7{l}3tm=c9+LX$G;t!n=>5`6v_y>#$P$@MYUJ!g
w$GN#sA0LPou~3tmd46jY9|rwsL;=VIBtL>>N!cH5jI4Bkj)U6h}}}ksE}bPMTS&mLe<{?2JI{>P
AW}2tH>f%P<IoOABdRAM+%pBhmysv7|jvfBVJn~1lOFyLeE&!Ty{85K7&FBG81h%fMN+AA#%%ffE
5tw)*R^J!-@>GTG6V;*d8}|Q8`^%7K1R*X?ka6ZK~MAK?xF2TirY^D$ZHM^wp9|835olz@j78aFg
4Ili7gq8l^!HZwae2Ru-R;Sq8CnP8LZTfpd>*T-lP9Q|m9!X4xvUC@I(M(iZ~L5SkWJu`A&1SP`l
^(My!r$Y&}y`*hp;;S)bfR=K3M%Pz=nyc3NDzmLV)kqnwcS(uPLAXD={9Yl}T8gi*EF#FzI_0bCU
(~gRdj-y_5KP5qym8QY6Ao)=PwQ4r*56}GIOU;~>IBggE`bpAog1df9EqT_YwvjZcYV#_y^gS+ee
n%{w=(tC69C_69*|O4F-;Od?fr(b64<gHF<n(N*8R>W^{JO(HP`{L1Q1Y~mV3_z_bOIx+VKk?7J^
t1VzOFPEszgXwuk(}8$!SSa64bIZ183iZV^!O?)ClKImI#DA&s3V8MdlDooUgPO(*3Md!8xF#>Hx
9|ASz#}0v{>DAVZ9a$<qd7GNG|m3Dzpcklf89g|#|HC*!D#WJ4)(=dUcY7ciozfEZ}|Q)ZqGPJd(
0U*$3522M9oQQg~+8W@Q(&r7(AS$nt{TN<s*wcuQ%gDzf^z38Z!2G~iNfUYMU)tYsAs?<c7SB1sR
c(l-%)V+;6`s;wdVmP7Z9JLX)LwtPe5@4KTg$R#IPH1JxaqelQ02A<X!cDSYW8tmHev#?8^n<3M?
h)9R7~Tg7W@Sid)`utv<V0r1G#tq8T6mErt`qQCPgbe{d~o+(NVHK?g+fCS)|pu?u^iVrm3yL9!L
%TT#$aPxiwaR{c%4Uyk|!B+Bi$I2FtCoSpiy*T&5}4G!706OrJ5{UWwUJmP&L>J1wP3Ov?lf%Bu9
Ie#LYc-BhUG+qr(m86U?9N7@o*h`x)Us!~2P98|SAMgS4;&pE+uB-49Y)LD~41BesNLE7TI(4nSv
QwWjSDzV&0N5vJ{g+JmkAWm)O6wP9U)D_6kXf%aWcRYJ4j-B2Z5oh`fyUp@gcNVp`~79~7q4@ye1
hyoawG?G&rzM-@_7cqnSvZ~}7f=Qei{TyWl8n4F+#6u^9u3|Y1l*ChlHyUbHr_yY!6$P!6$aFTRy
F`vnY+Q<xuMVakx(Zt88M}k^nuPG?x4wIY+g!rE)fmspD2H|m-v-bh=Z@2u%1a?9QV3L1P=u0-^$
h5ZUm2E;=843!bvtZkUZXO`eGv<rChfO+sn^j;8`$Tp?toIh>I8S%a&WVa{oolXX#EcwEA*lt;q=
ZT)RdDf4P{>>cTkC4&Tx@4<3e&zOX1NF%ZOEs7o+0i%X4EWMzJY$VNSv*kYYf~1afRjJEW!)16j?
AW}@1=z)(d-HKr3zS%OBEkkCyZUBX!<e0!G3?K{<1B(EK{u87P<Hp^M?BGHNsT&b&9gd?2jv#=MA
i}8DtS1@RPqa4;mlSryJ%);qXOpaR8!H%A$GGKc(HmWjXgw<jU<J#+ED-AmvJLgg^SCXUdY3<y-2
)Obl_W+mN_!^L&c|9>VbaY>uI96J~)Bmpw+<cx&+qqH59}|L^eG4(at(#zk!gKM{RoO)@0X%CC>J
r;V<M^}9KBn45!*kQJ5|eO8b{-eqE_pZ5Yf4xy<NSh26uR9gzrqZ261H}c*Gg!w54_eoV7dThAT-
ZPOz?zZ)X$N)QyO&G&P57046=jw$a`KzV#G{)cu0X9G8B3A;k!eH%&<f9^M3c;)9rLNzf7YKFJHX
q86!nZ?~D%nY$!;k4X!1LD}CATp20bX)(&wX;#QQ;YKl&^Kv8u~K3Z3<NxhKJenc?zlbRw8#zr+?
N4s`LmK$Tn?hZv-RI)fbgg$n(eL(X##umPoK1MNqlgM-Y=+q9ALg6yvI=x_iA`~h`RAhJo=m>0N$
4&xM3{R0>z;BmNQ2(~0P<7nD-efV^8OEk^LILPr$Ul>yo1E@BT5ntQ1GnF8nH5Gg`2IQBaQcII`4
s=*8`pX$+V4brov6=0zLSpK@bkkDW+s}mp%5fUKzE{VR@IhZ3#^w<+EP^9v>LC9#VUcZ5|_EKUEM
IklE#F8hY#6ocCZVxyGZ8;4?`hPMLB^yX+9?hZal2%WKmX<o@9=MfT1!)ibfhO*9=vXnjo6Zi+G3
OMuw7*Wx_zEIJ?18vHczwOzKl`o(B)qceP$q&a)$hzNWb$vQ$q5>|v%VijUaBQFo?1ef0|i$9SDq
&go?c9H#nL2EWeF0YiU{N!R!&%aQfNWU4K2&12MDojhna9hFw)Ae!daa6`qW37nV(ShsyB1Y_2Vg
+q~f!DFlBohiu(B3z6}FC7?A21w!s`8Y5iF-p|%;lso;nY=Uj>ka@7I^L$GZkYQ>w8r=jM#Iau4H
HTXKD2zxVK2P+S~Pqp%Jc?~ns-#7!^7|r9f%rAd{pmi^<`Uvdi_gFOeuoL64mMyevHo!tL!-{NM(
wX<?Kyfc~^v`$Z`d3Xd?v(oo|H;yzuBE%S~Zyo{D1J7kqi@qX9J&UIg)DR`KoI!XVos+DgR+ABo6
HULsaPkdzypV~-J^=_(rV7G^&%44u)9^!$Lt({9z8yi<x8n^d9})Sag?*GHJdvSWv8c@)LI=9=Sk
G;#oV4azh}itt1nBrBsBQCH}-YCu4?H1y{ZZ}-t=!*T3yy?3umXK#4%?eP7|pg?;UE0C<qRqZ0?m
P`O5t<@loc0B1v5;N4Lj^KnRFn<3w=~*FYG@{dEGkDI0G^6uI$Os*|%~r=T<50)OLo%VwhMmUUmN
DF~I?mK($yR1ay&ox*Y~NT6$~r)?y2sEKScTuK%zfV?PHi2qwVPeXzC`1fVs=L$=0{hy)=6QE)ty
R2@Mxq09S|SFE~?E{IoY~*zd!s*{m(~x2_$_CSSvB;Yut*zlAzH&;=XmaWpMEKhf{n$ikjn!b<=d
G;opJ$9qM7U!CZhs3nvlVfM}CMV7#W(VM6?#ist2_@%kd&lvDZ9W{Gx&#J3P<^z^%T@VhSOT@H*%
`C=Vh-3VZeoh9boaep-0J!MYec!-}xKfqr)Rv|lVq6y|K^!H<+y}$n+e&81o;Y@E2HQ}v(JmP$ZT
p@=0f0SUBVQpK{kCWz-=jZ2}uK82NZgSwwF8cux%Lyz6CJC!3O8W$cQDn0YF_O$gQpk+9lv!r{@$
ez=CA*#In1+E)ypCq#C34<>BYR`J&LghFV|FV^ogcE|!m9*45RmG}`@{|5kEwVsdJ1!Sn=Rg_n3U
P6_6=7Xcw^&g&jcpX?}6g_*;V(3Ty+?%`u4J{$+RJ#jBw%XnvZsPg8g94_qeui$i9_xhtAkciHys
fW*+eXcEiokTyfTKk<4@|?yp+lcfeQRTH!F9THkOjGIzxzW>u6?KLyBqhITNOU2%VR)f&H@rA4}U
Ru<>^#d1NJ?MKXWT8w$Tv$MZywU5yMS7tnlmPJ}s<s_$^F@(Myw|as_4!nuBBs(KK!@Hws_cuk(O
;ya)Au?DPcvG3F=Zx`$(#K>5=ddediWIkxDFURf`#vO1QI<Wy90erWKtIM#L@{5hu;n<AXlD^;tr
48;p{(!uV#k(9xuh=i$0X3;IJ49tN0x<7xVxm0xB$CKFc#}>BVVLacF}0IO%5GmFn7@pPt{*dLzt
GlS<qnZwce&C)sse461D2vJSN|oYP-?F_uo?&)~aLsvJ|-AGBn#ylJ|VYsBDQp;Y*#grqY3dc-cu
!g06)H`-*2Kts(7KUNPmQv<OYmvFT5Xri~kLl(@8s=P{wlt_y?~z*C{9{whht01wB$r&T8sNk#GB
J#E=by@E+YSoZSe*9v;JgLU^C0;(p=cbxN@=sS~_sion5qhYS3Hxy+MhP3z+g0C+n!RDw<+6x(&s
yJO-Tpy4kd1P7GB2@!#=yUIIaj`@nh`02{B9S?}AG!Mhb$BGfYOEA!6$dA$Kv2v_rqUJ}?&SsLG7
EDez#LHg9G1S3jk5~gV8Oj=#;|HU{$4trj#X!xjm7PQOXLFc-~JEE!y|DuD6m;OM}(&OP^F})rn8
Y9cdJ}zyG04uTB3Qi@>5$gE{s^Ta!|T&JK$CnOPP^clx&);>8ab5zF^mCZg9*K+N{s@&7b{3Ax|d
)4<s%b*Qf*9(oGU*vr&?$E~}_VHP^LH?4Q*<Gcfkp(UcP?DS*Gl0m`udi8;MiCbpD8=`c%(U-N0D
^2}(_18aH!y~c}do~43C*A01=U*)vo_1!!>$SKdeisPae1hWT76u8%XX4bY_lwBQxY4vJPO9{_Cz
mq6b>)OVQ^BXL)8a!Mpm<<diGM}|HsO0TV^MyUue34CR%sPB-Oned60Zx__WJub?qrw@Vv1$5)ja
P)qv|a_BRSAbxJp<{uvFZ`)8};$w1dl4pG?o!PyOn>39uVtd6|fWZ&~jw9&AUgwpqGurLsUl@xhb
|@I60vU08wJE*OOCs0vDW845pRck}0#LJlRAYIr&)4FjE(x=X5U0e2h$n{rqEDikn?(HwG77ddDx
xnhfnFuQS@&Ui5qcFq+pA#DEP-d9K(Z&?8iA<vQ?VO7(<UMLdZJLLCJJpmn8h6ik)?Zj9dp>4K?P
Gj<-D#NaEPNKyWNb+Yx9PXT_+?yMGya&a{QUYDykEZVTJ1TMgtgo5Uw7a+iT3`LXBYhD&5d-1v<b
w8YrAIkD0`7$H0T6ZaQJaPnt_R6WYeNtK4jH3IM2)n3TBg=C`2hxxf@ek}2UffGK;VPD)Bi=LT0k
2?5@ms}eD1qElT%u)+jnEA0#cOd#Vpk2IlT9pTZM(*S_c)bqudc2o89{5C7`o|!B%3wyoO`Y1-!4
s5O|b&9B06Klm}S91Z<}pwuus9bz<NVIE6Q)X(W**cW<^mh*l@y&2^oO@_JC(z9AhWoAA?$vB!Sk
}Mk8K5MTvr4wNz{cD!;%>$<Tw4ggabiCbTyq-BD``c0f%U%JFD0JRP;Kn>mb;l018<yDg2`ZWA#$
BT)}ukdu|l+RP{HKCB8Ib>wd3(0Sr}^>mf^o@CWbwo{DvRfiX61o+~<iW;w!a4iYIlcZ&O{Fs8R9
Yn}VkMT3#3;1aa@TocGBf|%fA2wcMqyyKXAPt>9QWmb&$q6a4Br0c5h4_It*f=t-_(neKh@t@3Xf
g^<D-KLb`M}5J#{;x-(j!++4wlzjn$OVQ%z6aJd@Pt<XEngP0|WWF7bHC;LfLzP4xHnPkdgD8$f2
p41Ww@Wm$6D1R(;GV7?HNst9*9{9*>a^tlEAf$%Q6nK)W^bk++6EXn>AF<jRj&@iiSDbdI4yL+Zs
alDJ2?yh&#$F6JtriF<LJQA_|GG?3H!v2mo`SirGLaR$H=*!lKMCN%t(bo`c7PsA~bU1vT)qDtbK
QO*Ns_FLo8#ngMHcCQ!O0YT^T0As}79n8|JvuP^Xcp}QRq@vex=$hSAx#|brq1RS_leEq*N^bJ3o
YG&D$e}%2z6z=oG$LdI99XT*!zd||oH#04BPUe!lLPB@piwV_kn*k+J4B)9@bHCbIyp0L9+B0<Rm
~ACsG<v>6u~u8_a&i|%84uJnwK&bQM993RI<>P>!gvWfpa<}n@839ya<DqOwNun*qEy_uMYW&xE8
1g%OPh`KZ$^GXpqz%HwE4noYk&~emW~}qn*9Jn~2Evo%0)19xsS1JCYz>48$?oGd8P^HF1&Fq3;D
Z);3mFeuSJ*UT2DI%M#gKHb2K@vuq%BqpHs7qk<$<Bb8$d`LcGCsG(#<<zwxNi^5**j2o_jzSp7U
TR~i@PGr))&*r8ZG-{{yl&5w$<5O@NXsA7wwc{`CD;V$_^AVP5?lTr9xP9#-+n}M(+RERtKWk9;3
eC`p4pqh_vEcX8Fv<61^X4u|wu@~^;!~jg(Ih`6W0J%iE}^Y`F?X(WLFv4CYuy`MXE{GfUHcr^iL
Pa>KG$W=&n*&kpWED(&d0-;+k!|fHXuOR@W>CY3>*(~-73&0F=25^)RNzvLE7kIM<Jpt%$-D6=zv
3xQJD_OS>NOn-{sNr$e_fuW~Urqji%JddL8EZ?UofO!W4hYny#iuR&&i(>qMMboj0yn&&l04{Bv^
q*#>pm;l1Ox$e!Oil2*h0y(XVLNiqUYF%?RdUP<dczq!|?in@b7YB_~+t!)EV%es$l@JV_#2L`ba
DNfpOY$bRXF6>wKw&YL(o=avU>cDRe`lQJ;SU%{EnWIUzM`GD3y$jGLoRr#<zg{dec8`Dc7BBesZ
-sLA6D3`yBwjwiMB!I+763fbZlyF=#r@9(Z+UN;B%4^a(jQ^$@lIKt>@9TAb)IuJzGd~9%3VXMqH
07|nbM;u26D;^SF|k?%eXMc(4i!rQIVD??2$4nMTy-xrDdnsR4R6rX^*>NqtlxbR_FspG<biRFW{
tCDxesueJ!n4>AA{U*{T|uk|M)vCD!K#4#E1i*OOuXLktUd_9fdQ<7Op3){F<GXVA41axrk5FmDO
j*j+b-Uc~(#*f}hWBAA1DsE$J=aLcib?MN0ZC<%c^0#U6+#!6v4a=<)T!Enh~+~S!-g_(`!Xq?lw
Lgb|iMZ)}Cu!<RPFs}<QO0Q*AbdVgMz6+Pu!E+jTFj$_c)G^*l=nrqz)A3cp{pc7qx{eNgxga$sh
2Lpe4@P_xV3j`xi@D8P&Xd8?C{)A3E#?9zTcpWe@&2lwt$eR(q+prf0y2cAL$~1`Nfa0+6O=>+$*
UH+Fqr#F%Sk(o94PaTt-o*D+`Tg%_IxKRY<$<%xkgl;5zfmV$}3|3)4s|F)*xtU+se;XD$AH~ney
1=6htUjgk}<-?KCua+eN55K+2g7Yhf*PDlFNXPPCklF@ev)$rjl#sPP}D56RkQVRmubM(9>dj~gj
()Uq6?4=uxB<a{j9eJU3M@4Bqrnu@eHsv=cVV-8m|LhB~<wy=E?5A2|EkX5K-j%k20tz|(rbU~1%
91+}-9mt|hn`Q+0;bYb=w&PwxqB&bGK2o79?pN&|8}_AaxiX+4{7liWl0_*<yvpT3cFS8ycv0+g(
cq|)HA*;=@aL76)EKIcR?e$Aw~n4%J9i&eHqKh+z-;^`6By~iBlhYLS;`!~1a|tIskBHFk~S$Z;p
(CslU64r9!BaBliL}E%|^NIR_Jp@AZ@j}O3Ea8`%qUwYGA9HmnTqb*X$dFQ^Bnezi3p#S1{ueYU%
-?A{&jb5TTJutetIMA#YNFoc&Rt=thZ{*K3JIOQQreqm|M=O2R4Bau0Avg~It*uhklfpONHmy7;R
tQ(G<QY>QQyn4}0_UHMCF=%$<cJ2!S?IlUG~Fav8M0TTx~DGNq^7~>&VDP0%YMY_Ns6;%t7GbgTH
AqaH!T`e$&5-axW-vJLUEEE_2#^dbCC$va2OwKhEB)1ANiBk0Qzb?ss%Az9;4cTnLxN1{rv%($K?
XgNia%w-4^a{>1l{MkCwI6h)GyTA~e^o!|KW255pMUX=G>kZc<6qmX#plfIwbS>VRy*^Hv{{oLuC
0mFZq&qw>uTzZ8iDm`t79^01QxKhmdPD*vi1C@4-Z)cXj;(8a3l}Fu962r;X$kQv?VhzO{x4i?Sq
l1NTblfR3Vc>{QPeL8#iUb5@Hb)wP%yLqm4;z7ATu!YiV(ZA;l=b=D&^#ZxVm^qQ9wZ-cB+f%9X=
ub|gntUXuy%6-J83O9*3-E|!hv{OmoHw};KQt-L+>jS?Q{L?|36z88|&g=2w*wpU*3RH{vt{vAtC
tpqG?4k3xBZvw2HmDegcI&4rtep^XyyKk+Cw9;@{kgg%Ebuj#kGFlcY-CV2gLIvcP#B*O&jeK)x9
$+gs{H9dmIf^LPi;hxhSkzBeB4<wc%$edPRU}TQ=Z6=q7wOnC>GBiRI(cR6t??tGHFG95FG+UAk=
$2;<`H$MP@&v1zxaI1RT0y)+_wsp?)QgNu`{F<Qp1s8Y9U6V-6Ymr(A2qoL3`6Q56oSro~*jb-0R
u&BG>bm?*%Vss~f(Yzfd<DBzjxD#V)v-gjg+ChDwv=?Qv%f9ncV+dz+iAznUBCv;JakEZ}Ee%Z&_
mpL;1wk~!55e-Dk~w<Z<rZp>&sMJCAJt=B~C9L1dNlkvWx_^T$@4+(|w!orALi0P*i=I%1PjZm)B
M8%mO3tj0}Q^kF83kABfQ1QIh$vJxgSJcY8vvk0fVB+uUGRx{VMEf~mVm>!qjK{S~vEPeib&dx_r
<zoz@wbuvI__E%L6ZPkhhhu4ztF0w^B#~lBLt20*zQ+q8G7|?-NFyLVW66W(oH6vRrI(>ox|ET6-
cUu`f*~%2i2EzrG~=!ht)o}nyjbMwyWKI+S$$05mtrq_$k>%c>2HUL{Xzg=BTz6L)oQ75*oGUYHF
_xXPXDKGP=$h`IE%n(J^<tb94GzyGYJNn4-lwZED(@=Tq6pZy(rEw0wLgR>|7Qi@r9Itz*D^KYG~
j6RKa$q)f%Dy4TaOyi^;W<0C1pr(^iS2SF86(f=gRrwg*mp)(_WyZYR53a}dh?Ont3j-|w5$AMF)
8F6$Ssd33ml}RP2dK5Cy<S6~6DvLn$BBg!%%=ksvT5r0%n#a0_j+E*UQY`9&fnMc?PmX$^_Q+V1Y
3uCR-mi|#GV$t1+F!-9=~k-@%h0R?y^5CzX?;5cDkLA9l=B=JMtFc4JLTMTf2!H2s^j_K(<GcIc|
3epD0jHwj#1KSflk$NPfB9KH;d8QsOk1YgP+2Y&(U&1yEy=9Pg3(K<uSyMG(m|n$7NJNtMn|R;5T
p~iy?`dAznG<_zB>(jX+`o^r^<IkzUQ&TsIzg?dpzo!^c*mr<_<GjjocGX}@|az!F<_ZVBzqd;N+
{*z~>H5J14rT+P`WM-3>6x-e>M`IR2Bb^UWTL8UDoY2>1+C2bBODhpGgdpI5q`lqd)KI|seFePd#
Lj^<X0Yp!tL4QTFfD(!3ql195LUrCu3tea-aRZ8ri3H_yS8iHjjjJ8B4%~r^HuB3enqw!t3y>C=O
Y&o7C5L1^H(V7kkmXz@Kt&(yMNaXhuUID2Q^A$tlwhpWS$USusyGo?9*^nGc&tZ*7ULC0p-2mKyu
-I0*yxGlPfCxEB@V@Dz?~Y=jT6eV&!)??aKx1CaEuaoIws;}JZ8Wjk1@aq4oLc|?kdzO)-eSh!L0
!FyoGsA=67%vaFDPq%v@s9D*%JpiRPp?;|xEu{Oqbit;knZ1XZWK31V{+;hb?kK-oAfQ&C84T=_$
Kc!>Jiw`lE$@qTpfo2VzRi~NcLOUb6FR1{Xoxg6TtkN%QBjVM0_U_9+SRz!m#XZ>M&PmaR|2e`_R
RnhZ-*(NB+%2_9VQUGk#m*>kF%~J%8u-ell#b7WqesG%=d5Uwzd-GyBODRJkNh_i43>YO$9<{hmX
Y>rvWt~bKZwxO-!@i;D1GFwr^I9UC!mOc;#6Pa;1tKG~kVIP?Slz)M#o2SizunNi4W|tmv?{*<00
0bL)EEzreeReGyAr1ZOjm|$MSYl2NNBi|;>EkeS4ZRbFaPrhpm1mSXm9_dc=hu2_|@TuXWwIpt&`
&QkFUnhzCV2T9=|@^;|Fiwy?k}}?&t9jN3Xy8@cnyE#)mK7A3b~X`nmgRxckjX0bf5HKK%hYJA85
U;b(Zfw|i22|Kp1n(AiH<Uw*)n18Dy3yQ2^9j*jr@`=4Juee(k~(Kj!s8L0r}Umd=D-FQA2Qjaiz
#^b{uUViub=(+R!5$((mZ=U_-!_RMz#xGz06-qs4zfAM^uSf5m9)5WFDk9mpc`hyTa+$|JzJB)R6
%6|QdwNGF_U)VZFF(9|^LqULhd0!7ywm3(ggY3AZ4ds(@Ne+_Aw1uM@87`p0Y<YMeuFWPj(+;^?r
<!_j_tsP1Ns@#&kp_U($7Qs*`uFF^g|)|{0r@y4*m@K^8Y~oAIkqb^8c><|4{zl!~d;7hvTzlKAV
o`WtHPO8Y8_EE8M3-V_`O(uW>?FOe_=NdBAgZaDH};*0p$>xY;A{#p6cQGm?!MFJG;lkm5UgE#>L
`g9p*j?I>XUq-qQvdGX7R^HU{IIL78qF&OwDdi<EHxLBQeE+ubp;N$7xdpwfi<>a!H8D>>h*{WhK
8#FPcs>&{jVHTYblds-C?Q&dc3HpLo)hqE1pe4R3&M5?QZgQ@h@c-j+UgY(79AgM6H|r!jL(I;5c
`+x3iSo(2uVAX~&e2mC(O6PV2VYiW3P5T(QsYq2`-DOX(pbDWYPz?_?3=I0<;#lB$k|)HJy!L6@s
w(=sTotbm2IEo4|LnWd@_tFmt$;1jMF0*A-iPUl+mYbQHuYK=%ipndf|C={du5^?y!-7EeGmB0}a
t2l(~m?MAVB(U{Bm>DYC>~ZAy*9QQ7?EKI^MBG+SclZW^q7tpm`}IoeO6e?o(+03`Mw{WBsv4y+#
U(COa8tV0g)B#E0Xq7}%t`JOTp&x#6N!5H2PENIW2lR$fIJmzwv01R2nnAp9{v+QGAA4pkKMA(2d
!)%rJ#9yQ*Ph@epd3S5C05`Pt9yp<9L{E^eV4AhDEstdxHeC4b0T=gyZsoXSbJU#FyK4n;w5<MH*
$A4n|4vr#x&iu^FsbV9N=9?pHWHiUvAeuOr;p1XUma#>mpvZ9se9<5^b;&zz^6tafaxt>O$ORk8=
e@K0294IL#jt;<H?gYD|YH3EI11y8C;qxxJKXxgewN#;Z1|8@{lz!-aa^d=%)cOf5xuGGQ1xc8Xb
OE8<_fl@I+pRCxEMm=u#Fu`IpSZ-P8OuI20Og%TBh~(b?d6*@I~uL*3IRjKWg~O4FP0ZD=C|2Ll`
8;d`F<sP&$w;kO;a8O0!DvM;8RKo)r%fq(p5VlieSO3=kNcZWozUyWZJZ~^}v<4A=?+|zkAuhAQV
yj$#5BMPjsWK8#9aGEhEksFH+42UX%VB+z5+?-LK%_uZBGr449903bD18B;!MrwOC6EiLAoy^2c%
SvxReW;f++htF!saar)$o2^@mhN9+4lThZUPpK?<+W87t`WyJkc@AjWU;(*XndXm`mc?e`aC=ox-
iW>3EM~TWC{K;TfKDj*~+<DmYyR6PzGG_h5Avm4Gsg#Jh4`x4V~~o6BrArNXBN`s>7t!R|v5Rj+`
R--nCe5($tznsop%n@-AOh5-HI-A1BqE7rV;dIcTS2wc^i2?mFDN10ewH<_HzR+p}_}4m4c~9<U`
yP0>rHGW^$elSJ=7W&$n%=l&}T!s!4E9<GIK4c48=5pMi%0_X}>5B?~yniE5-ycY&%43O_aG%i-R
c}+BC3#~t~RDP>W?^h3$*mbhQI<SvSYu8d%0pyB)Q^_H$U=#slrFTJ!P_Xf|Hk+C`N2z^^))d8oY
+hX97;CcaRqPdM_Ye^9vD<H7K0NdSXz}17fDeKdv1@}B>(_$#J{Q7PZ@~sgc;)@kj)tY*1}bjQCh
+v`EE^L6)1XsAw2f!b!ZbEfIY~357^VQ7!QIxU^E~5d8BA9kk1X2cG#oR<BcIRGX{1SLqCb4P*%`
39U=$VloJg(3Xr;8NBZBTR;+T$vUmr96^qFRuJ^<9?1G@@-9S+vXO_spT%|%DTl_N?m(GZ>prH0Z
s-<gEoOV5(ig02~BFu}r3b^*VUmi7UTih%5l6e=rU2A)f*gysuPdOC~lGcH;fw9s;&#V~RXDm`Rf
&X^P;4dCUqrJxzW2}!u{fNYRT=y8Q#W2kW4B3}W}kXqK5*B7-^yjlHV0rE`D+J+4G-<a1Ap~BS%9
NSRX1;`|%xZ_LX05f3v%mc-g#Z8q-Cu(R*e7L|h^V%`0o^2Gt1ADa(3{6A7k_2~s9B8bm4I;wG*U
b10rnCH_pcPb&!8jUv8%IJl#`r=?{z-ayIQqAp=-NB+w+iQDiDca&M{J|`DU4jAvQ1P0<b@3$-{L
KB-9X~EIBzxF|B33~d~%i5m*v!&0cj4$YHT$6Pye>jUvp3~nn5@E<n)R<6JOMGO*iYK4a8#Ds_Y7
x^LLb<5-_?WYsdTL))0%sei9Oo3iQ+cL#wTkEQdkdO~MzPsu#ZKf)|xkY3#D<RGlCaZ(yKL@>XE`
6L@v9#SDpmMqHNsmLhpCY=c`C%-y150+z@d>8Hk&9l@iTXVdoW6Ga_<6u71DLaS)<D6L>o@7jo_T
h*jKml~%1OfICE<H7B3Hn@j4xMBa_J-Tl;8{ME~={^mA*UmY@>L897CjXL^xK1_-0kL{)fuXJG(q
Ipfs}T_*2t+bHX`+tkorY8ngIxWjvcs{-$VjId#l<IE3(3&Qy<pTcHu7Pk_9-FDo=uPc^!lkp4<h
Lu=cPrBsMvU@ye(v*!ahzEn+pA(Ft@1_lvs~~lf1J53kDTW7k3>&0LEmaBgQG1>H~)+<U?9mk*2W
3_cmo+X(<38^jBq3ewUKt6d*Yvqu=ugsx12$2**WcQbYjq_{pE?Hl5V7I|=1Q_G1mPWrOIIO-tHn
MVqADws$rxpf+Yok{jKIg$4jgNd}+NRqnFUuA!uj)s?)}Y3L|*nDZ86HkbmfS~opHM+)VV{5}Eim
vf8QfvBfrMWM%yMdYDTigU}zXWJ&Su~b9qo9&~n#aS0q-<^d~Z1ON3n<0fmQ~Ol?D6GM0Ak=2DU)
(`Enw>wjE2cuN@3k1b|FU7(Fl!L!B+uAGCDbo1m0bSD7p4*#C+<v|G~3XOFJ~PnoIcrr*$=zUDSK
=+9ExjV_uATuKURXbaa~SJRm<Wnx9vu|4aPL2n6%n^65LQV?*<dNV*k&ZY@f~dIVM}UhH;aL{Bu)
~+t^tK8KrJ(0k9?m>Vex%@-Knn{q^I~xS7FtzXgg{@ZpWdd~jK@C76?_VO`gWnud65g1M~RYH4;|
3}?9XJ{me|KiMEUi_O9koAU8=^SupWOx0GHb=gR5jqHr#s>5=(upJ69Z;GAajLHx9eosxxHEhcld
|}AyDBOB2G|#o!Vgwfg+t^?g6a?99-f{o-X#aH86|+(xv^w;5WAWtV@WKb>DeJbvW;>h0;-oFc_v
hfrb-3{J)<E}+C&e=C+i=0Dni$#))&i>ENr<EfRtVZ6HjFkj8CAuhTft}22E%0S$?8)W`MSq}!a3
FW^8C0@snP*p$Y^tevpop6vpd@Vymp4+cJ?ta`vwiIi6$RBy=>=?Flps3a#S+FoQzT4br8Iq!eJI
vohKIE(WZAd?VGXzGbTg7bPsf;7E;i^K%E-vNS`lrY1+4U`)Cb)X39TVc{a%(C1dl}H4+eoX;&j<
r@_bOQdt|E4av=8pY+7L*=}(IBx7q-*2h3|Hg!$ecD;RYHK9R0`&Cuy$)zFboEH8Z1-v=dtiIjaL
8$&{EosxZo9I6JJ%o)6MD)!?mZ3)%MS(+YL|#SI@=8qBSflOLP-=}k*>KgNMeSA7MhFvl%_zI3vq
evy*czbFVp65`7bK5J>+a-2X|Ka%fHXeX<n~<*It>+HUp*T93r9EHXmrCBqZ@wd(N*gL_Zb%wy@_
Zmy~j!e<L7gXuTIwt4_P(GcZ6#Jt37Npu5L4bp<&@jj1b|E@lbBV(avb2ILSOG42~FktP?lXjdl{
!jwYWoL8swWhg_JY&uW}Nl1H}zgRo*KJjKuI+mK@$oi<<n-ruA+9-FJrIwx1Fke#{*oa@xZn@?;}
>F2U~)DqIx?AIj1RP=^yAsn^82}UeCSR<tJ1v2)yH@HA$iJmliS$}zk8sKlg=K|$blGe_$I}EDEs
)@Ci<}Z5MQoZ{bYbKNV<+Jv9;~9voeBBJH#Uwg##PQuWIhQl$$5Fls(nA96m-XeCp8jPG9UY)$5l
~O{1dd@gr<>I$2wzXS+RL<g>0dS=bj{+g!92V+`G#xrN7m&t)@1Yb$k(jJ26O^16OFFx9Jl{pEZi
!qUyHBW4Eu(-H@D_mj(>$1;fsjPSl7Dg<rA9FYTn%wXsg1>$|%+h3^cOs$d_iX(Q;U8*AJ~(EBya
H;g2oLdE5&6L=YTA-PLP_I$kXJBq*c#9J!TTQRpg`N)oWvyQxhcgtY^S3K}5LZ7AP>7+tCFYYdld
BGg@K8#Y9g?Y9anev9BXjDFV3YFnE7b2NCkvOUXFHB`4T?DKh3Tj`acFok;k!ozfh+?sLn)WWW6R
w>OX>;{L!sX`HVj8^`5bY5BL`FuWt;cr8=({P61tU!VLIoXm14&O9<CMU}UTLn1E-UcEuy6*qCyJ
u}~+eq@Spq%n8xh4_5B{9*~I*yX{t}Xlg*vH8%7$PAFF-R~3X^D3Ezh6HGGk8#xl>2h2ltlnDJu^
MsGd(^1s2FNRC_~zhW-wmqS)HpR#<t|q&T2NFU0E10ITPXe=Hze(hsqdt??t<{ap8G}8*zmKoc`4
@jAv*LHfh@0@Rpa+=~A=U*9@dBz5MamH1?yx`%Zrt^q0~qZ5=Ec^UJ%xAR&^TLEk*_>Zh(iggPYJ
4HJKz%D4x29U{%+pvHsAOwh2-KtaL+Sgf&^!J1RKij&+bxN*%n5FU@S1*HlDf^TPHOfy!ankOEqm
h;xm#*0a*S|Ed5R9L#IHBaelZg|wDZxwZI(~J7m%UXuYoKUs593S6uSljJ!V1u<C5B7pu^i-&^#j
4P}lqCr&Nt?ntmHo}xk1MUWIKWMARK}K0S;NGn%Exfrx#@P`zorv!h0X4Yrit0uYZUAn$&;k%EyH
+4nWDv+*tWFOblMET>UnXji&P4k0j|?EXK~xi8?=JcJ!Fd-rJ!<Dys36{WGV>7#b~f`PH7(P(bA1
5OVAC9_}1b!ns#i=+?=eLNBuG5cH1u4=sh{sZupK(s8idGth0OO8tf+IIH?rp@6eh)wC%QZ1pnnV
T$O=i5LB80%R5MuzK7lta|}_~vFp^#jC5Wx?Km^lAlmhAvW+7xV^iBqQcChyi3YcdF9VKoYR80o6
JN46b4oG|2YBP~h_ErHY;hVUsrT%}%RWU(v`!Z!#{BZy3s-Xv1NUaLfSqSS!S#PiBFZ7%`1tW$ez
x0acY3)((^q&{Zr4{S#o#mjfwvfE@Z-m(&q3udEDi?g%cI4a!~)tI5cy!m@Up9TDdE++N9}XWR{$
-?%TD*>#}5nmA)*=<=pSeSqOFe~*(krgj8+(Hk;db_PBGsx8NX)JRlHnFP@egR1%<wb=LJA8NJA(
TR}@Z}C{J&_6aLiZ(09*aj6Y!D!Fja0lqAeCg<HOi(s{H-Ti^?{q>X8z!q3#}7RKUS&})pqiadhZ
GB9o`Mr!)RG2l3rFUGp_3ElYC^DoYC=quvtPizwH|2F3+{~Ya;=IvC{`f}a{44xQzzi;5AkFoT;m
ocY7UQ!M=Ai0R+1Y(eJ%qpDc6XvM^29!A9Q1~;(SzT*NiSu-}<&du&8IV#@(yWG`q6LGcu;UsZ_D
>ni9aPeYuNYbZXAUL>2|rp$2s~QeLA=2`G>t|cYb^2)i}zWcKFm<#c|8rb+uUBx5$!gTAs+6sHAX
|filYm|2#j*uF8Zw91{veSBlw4?NeWEx1I{1-yNqV^xJcVDP5KjNhkxQeefsp}$;6J}7tbkxA%*4
D2RLqCnFkDMAU`=@T>iMtEC}bz?S}=S8>?f%%#%<5y}>LS3knPQ&uF?%=^)BMteA~3rs4+hw&IwK
#E6>(MmU0#M~8oMJ}xBd$ZK@`PQNoa^yXwFk1?yi!yufY*Yywk@b)6U+>n($5ynVC01YG@br_#0i
z&<%`owf#R{!?&#jD``>GOAQgV!f-f|uw4hc|2;XwCcH>-*3m_xxYvs&h`O2J8*#ifOlnJgUnStp
}74&U=qhC@&-tHm0v8Yk6csX!YllUtYa=8T|C>^n`-)>6T9`jkk=F&vC|C6!}fIj2BVqMc00_h)_
Y0KXazSmJ2!Yrb+lYo+b{k#M>-k(E<{4-$L)B(o1B!65LfK+*KvqRTbP-HQWSO&dV#e2h%XQD0UQ
6O_cgns=F%HUFCIU+h-Cz{r8D(U&@~BQE|}qFv#_qSKeNybLd607|8oi$mh{?!|_ri&jEsKAlbeB
$H|M6cdt$Z1T0}+STLD2C9{kqe&IT>O46!y)AC@c`_h7iRQV}?cikLI+8qo#3J|vxn3mXug+Ov3`
3@Kk(;uc83Lc^Nu1!C$ukc@7SJ=}JcZ4K`75c{aenBqD;ymB4-{~F>fpDSw!QWp!KYeGBZKF3Fwy
+5Nhkp--!(Pj4<BP)s`-A(pOMl^z>wTvJf1~q2I9&(MQKyT4M}vc-`s!6+dO4W(L*Vo)hjlnSyyL
Lsz}x8B#SRAt(!cI#upgYEPMD3J{=t!;x!d1!T%#&D!!E`mrE!gh`@s=k&_>_E^F2CrSPAGJJvyq
yG$EKfbhsxWDn*YNMMI*TZue-&fcl4fPFYt;S_W`H^^QhI(xXnVyC<NY+apG8Z=isB!+m+I@AgQ(
_c}t={b6rUKuXq9@c~F0=3Qz(3`?UzpYD&QgEE?cl#V(IsJm~Ml(@S(7%tK6A9aN)d;8+akT*?Hw
>Rtvo)qJIuaHXLJc@3o&uD>N!Y24V04aTUnN=UsC#CQ%*L*;y`qe1!j5@M1^$tdRf>I*yF(DldMm
)Ts46k>z=j8Q<E~L)UAwxPakoF|a-pGOU5R@yC_ZTk^8Qx(5)C0zM<bry@0Q(&y<IvW0q$^9mtAw
y8P4&Ajq=W8(Kspdehy6Vv^&Cip!J#0kd#HWdb7|=-o%gurLxwjffO^3AhAyaw3{WY(Pi+r}2ej}
V_4~X>b%*=*>7W4Uh$*T+5Rs$1@7mHoEI{h@8B$l4mchO|O#jG*MEe0i>Wu_V2mO8J%Z>}F*CT`<
9E^_ci10zTh$n({IPBbY>IOXrQke+42YbpH1Eq422JcS=gFz9}y~$uOEP}c>9SlYVP!Ax4g94}rP
{LseSNA4`BNx;IXkln5oiH-$47vqU*b`GjL+FPLh|h8sC5-mmVups$j~G&?Qy_%Vo_HE6p%19Q@P
PMTiw*|+LQ+B>FdKIV%rQOQ-aGx?o*Xk&G9R!c^#Ft`l@Epj>HZj3Dj$pl)csMeR6gKc?jbl=Dj)
K({{BcGDUlCZZ_(#X{O&j(nZsv~6(Ieid!l@#M9xd?s6QCq6XPRu{2Va5$P#>agpZWSS$#DejCcj
^$YL_=?s?cBnd7I>)BO>yL_TD4dI-kN`SVaZb$^sAkq?iAU+#}{CGwFF`Mr^T&@n1o%G+@h1tI3*
rO5r^JUagH2z9Nhz0Gr6^F7E<=-Dh9-8N}-J-c{|b9kqCUzjfJbX6Bgny$PCX+@jP{kqtPoG-UN{
`9pwnZJmx?L4Y@2V|8?&wq<BQK*)Z1SoRP1f|fZD7snu*)&>2@RTGGWt=iKlX&r|0Z=RIe2$~*fU
=vL(jip-j7C^cBd?GyGb!PtP8lODHSh=E@#N>{@63fW;zaCQ2yJJ*30-qA4&#NFtBAEbbY+q!;kA
<QR_M9m*YEK2cl>?bbQAMhpzTZ{c<I84VSLoZ2h<>;^TQ*c3(sUBr&gP8O$w=k%53ZcT0*9%o42D
-X<}s3qOVd(xI)_XIMW2BaubW$C*$>&vcutvbr>gf*_qk!%nc={(wSZ{ErxpAh^qHBUX}{!5pMlL
zX|lQHHIf%BfoWPG=9IfvDs|yVTu1&xvFd6T^q3-AKshI0@6&@RD5XGPip`V0kj{$YzEkw0DBYsP
LKP|ZhYZ&(437yO6DEvLn-MFzC5EYOnfPREN}U7vZKN#!?d)E1t7o;!)c96u4r!Ww9u5(0A0wL5;
W&4&T+uS=nWU6HtD(LrI=K(w#|AgWUPjH5RQ+z_mfhLL+!%2m_xT{!gvv`09wXwrZ)|(*YZ9^+v6
mhpU==Z1xOUll4u!d69$^TV>u#CHw-wp6x#j5`aaw>t3vY%VXxKe)lYvvd6utVNqX6Ew}vq$qvT7
yJX>#k$%`{nnrm!B>!xlz;p#FoF-72kg4=C@LEz_^{_v^)&~CepX>Ff)-SGr*!7nI4vXo>KOI<1@
eIq9S%~SDycw`I;_$m|o1Mg3vt1Yq?u%9Sl<d{ocMze~X^iboRl02i`C06;3+tEkdlN6#P{-xpMh
I-;SLNA#?aVSnkBh18lO!zsgAjfM-)JhnVfwl-cG&cT;<Kka5CjQBtD=r0$w=)EL)*DYIPSX^~yk
KF-?~lD+A^jWo`<R;|6AP0iv(T1caZ--q>om~a-2kJ$rUCkRrv^&ati@s)F`Syni5i&%_AIn_F{$
AsiRu~5$V4;4YMHzy<+lt-QZZbi40=6huUX8Cp02jYq`1pv4P1N4>0V8L4Rg^h6X1SHN#0xDbqI3
Jj2vaMW28t|tb0loyofezUJ%e?E;Qy}XnD<B^K`SKErO-03PVY35R)3?Z_TzE-NYHiCv@Y23mTPe
$=bxocS(G{3eg(CN7F+Y2a0URG>??!T5@umWYc3i*95*%=?(V_vg*Mtf_|9P-C9IC5zc0uYS|LIx
CC1=Q$Qmdw7cm#MKfalTQ>@%XKQ}QrpkijlY0}Q6WX>5-U@hsDcEYx+I9#RDzlV}$n;UEocPF0DL
+(5GdeXD=)4V&zPfh-oxXYb^xgY6CnaW=u2{94F5)z(ol5(`{~4RROvh|Y=Gc&pGCya*EMB>6#sa
bIPHck0)+U~nlO5jV`RmK($i!ZS)bXad9SP)xJ8$7g-sTsn=R(0w$=a0<Z8slNu6kx#*hKG=sXib
5F=wqO{^w#wXx=P}Oq%B{&->1~qs`8E=A=&G2{?9hrqfI889@B{&9aU@|E*XQUOA@hf?>Ao<RUcH
nSdkopZ|8d+=zLq>Sq{0z<#hy!f6C8e2?RTqFJ;o<QFf@G(s(>#Q`)be>Zq=Eo#5%h<%SS5-y5+`
P8t9=2ZwMVzr>PO)xb(IX2Mb<n6m=rCAUasb0RMuyJGnBX<b)9L)*YEo$8;>IF<<^3&7{0R@O?%p
-?~P$XyqIri3Ra0T58$P^6Z^d+B2mu#%YHnn&xRcOlkV$d7jL=?_=YXbI$3_xT}nD%Qp`;z7K+%N
6x(AR)_(!gC72Y1Xovsnh%Yv7gtAdX<5*Wqery;DvA$pP1cGka03SY(UnDehIWy)a6Jt3XV-Vim+
Kz_}B(tM<#2w|@f(%%&(FG^~P;VH1B0ljYKm(k|L9FW3QLO{S}k{EaIMvj>qV%&v75!Aar~<NJ7u
5qjxNO19Dq85}VtEqM40Sas=;3+04}jRpL&!GBsLO<3*=v;@$nvY^A;kQBsDYA62UMExn8%zy+Ds
bP{dLfX240DeAsd-B3QpVjQGrJl%IW@br%BL@}y$M#i+aT9Q6t{nhPkp(%YtG(JV)Cf}7tlS{K_Z
J+VnGQDgdm3fwqnTeUlh3cS8rTw#N|?b_6klGg3(~Xguz?2k+xBKD_N2TSlKHe6h5nGc7odpv1q+
kSwF!d$oFHA`iq!tX5YR@|u81EquYJQ`zra`Ddz<EK7cOOF6-#Pk(Gxbk_Fufl7uFj#$ubwD;Axm
(tkTr7C1=;!b(+ppmqz+q-yXHN99gsk65lGm3E*s&;5^lR@}G;k&t#C8^BQJX$VIq0?oYJYH;|K~
8=x2;#*jbU*biG~bAF*LVAg<%%clgo#HYGYU5oMtsCQ}WY?rFD<@z!RrVLT`>@1J@qY1dEhH(N=m
Fkd~_h+xl$iC@)PYrOPme-Bi>d-xpXTc4HIl>O35{nwQ8-Bu_tNMn3dwwSewar0wcYx~N0xF-3R*
r}-@v`B}OH1oolVRo*J0ckEV4y7;XcG`bm}`ml412=gw)wXj?QK3kIu)jhMUwtzIScc63nB|;=qR
*ij(O~NFKo6Ur-=qn=wrWsQQFrm3g<hEedfF+J!}4PN0>IbRB&_+Ikv&x1lzzRM#9S)dVDLoRg(X
Pao3>b1eK93(%6$?T5Ga#y>oO?=%|?cmQx3TvuauzME6WcI(t35+rA*B>^0oZnW-?Lq~@yf50Vt{
352!WHeeMr*8<La_t>N$$0!4a-YmYLgz_lxA^e%872RZ!C{oVNc7L~_{?TJFIUN{ezTFWQ=%mBx0
)2p{5i>{2vnE#cwB+b;%-1ulh8EV~K#ke&s4>JszIn5O4RK}*JyP&TT)K|RGE$`~T!@7QYF=UKss
)#)F8(Ognx*Ro^#hk8(`Er5rcOidfp~a-mUfzX<BBij8CNRMiNs_3MY4e-Zj>GO3S1+2^{$D@@q#
M64C6(%cKi%e55$@z5%muo$y824KSLuL{Dc$){astoE<*GmlZ_g^1(T?aZlE)TI8ULiupp(h^kR}
P<bZ55Pe}mRHcF{7%Q+tNwlJljm+2alN}wCyES|Ds4ue~WQ{pPU&e%Kf5=1yY6J^M{-0e(QWVKmT
2o=^sQL`*bW0U~q*h`?>4J{<!(9?BEOU;6^(%4Hc?<@fqF&D_kB*{A(LTccf;{G<lrnuqd%B@_cF
+1MaPL&(eog2gdYrgSWd0eLC@CQd-IyN=j#X@$+eK=XpD}{Yg$J{C{=ZaOI6<f{1A<VhU3ggw7{)
KJ2c{a{DVq)LoKBr?iP$(@8<l~oKU|RDi!~{OPM$S@T?GXE}^pb7nb0l`4%&v8(tDjLk<Pmhq0}+
=9MFUAm1K8m)i8+lm|6+8(gkY<qw(mYSqTc)RgvwZMoDPv)zvHg;+?!J2!aC11NV@5XAI@ftGnsw
9?lAzq=MLeK_sz-c7f+v^SdoEjA~QF*$}6>UI+qM$o)4>rE3MOaq&bz0QrP`s3RK_#mDd(O!O2Mb
0B3d72OQff+yXo~^_6<gVi$=ktS>;hYsMFxblR_ws_<-0yxaUkg(eW2B!q=*2+<8GrhWs?sM!{5e
HAZp;yN!1q}&-CiDr(Dv3S|DWgplyP5kJ_m7;Xf%O!)`M2m@Tdvu)nYU+(yY>?R|!QnPgBDN*5*r
t4V^uu@Gedqn{<mt~RZ#?+PTA9OMr^CPK^FL4CynX)aH2;2JeLQ{j^T}KORJL@{uH?7)6`isV4Tk
&)O>%)u!{jeMFY+o)N^!b9Zg(p!5iD`bS{+b;I4<K4WAx-cr?%3AP^P+8Iz|8yKlVo#yZ>PdFW>F
cI4nJ|sKWwatCpvBB-nF29n;^f{QXi`!Eq>9i2iQn?-%)dZ4|*Y<4^J_2QEH&^Ze-xck1Ri^f*ic
L!}rU+1J-1y>k#|^On(1vD@hRv1N8tXMSVR2nBR@Xr!>%agVTA)|}v4eU`VC>m}X!`9W2S?ucs90
VMwJ`7?`<?;<kLCSXwZl^&UN$NVj4b9yWa7LGjgO;y!@fBBZK3t9MDz#1cK4xP+^`B%7~at}q{P0
se_s@JfZS})vfqgdd2mJkte0pN}PO~291MI0`&ugElcsDPy-_^a0_$yyexO0P_LyW=t_cb6_!m2t
&ioLG&#liN~UqrtO#Ey^5=4$k-s{X5xhgyxWi^h=~);4}*kez%%vwswJCMKpFcEjSzZ%7#!no`OV
U4fBi-XFMQ~2`9yrcDPS#`6e6*do{4k9TlDW^euoq>rU)zF9Fu!jRQ?y<xQ90bekw<=hZD(-3r-H
puy2lpp*o?!m81^ZAG6stA5quPPFQ)vJ4kw{sAkp5Z8_QwKczri+XYQ>zFOCW6m|a>~?Oc*)=u0x
71W@8BtY{CNJ!XB0YbF%Gcj~<~smY{yS7hUkW6$p?u18Z9uW#9L5B2Zt3DK?9RmIGa?rc5N&|#Z|
xpeSOpa)pUkW~9Z!E)5_)OBcn5pu>8~#;B%fuPY%lrBy@Vb4mN_@}>C&8m<-3nBL9n0EwU>)R%mR
y5klp&X-$kQEWx86hEu~~nYS~cQ<s^M&reLz4mBn?o^g&2x{BLJ6(d~@4_x&Pam+rMnfO!=Ex6sK
%&TYXF7%cGuY2f7aXP*6Lo!!KB!EPeVrg2Q~Fya~B1d9Y%XG_5^d<swn&3?dmMl9D*hfs|#ZyhB!
-&xb$tlX=%a0X$s$E(_XZ)k7%k5awX?cRR?C}kFN2DDCWa>FQymZz2nhs>FKTKgAb&iie{$~su}O
j(+(MQTY&)*<aaSGe}=bcIb6-e*_e*6w>#D=*B=DJ%y#V7{a;+Gy$s1YvAG28Bw73K{C>#Hfs<g?
(lY7$MmPbgdDjORS2-{L4@O4&FX{`U3Nvyr?j_t>;QMZ2YRW2HylTWGkAF@iIBTeT<jM`l2{UDZn
Rm=;*I6e%h~l73eWtbM})8vqxrH?f}lX8n(2&i||tv0OXYo(B)j>(rP9xa|7ErOH-(Iwlx@aJQ4D
>?K-`T$kv|t!9F%f7&z73tkVZ`2wlom^MK*Php~vOdiwv!Ai4gn<^8{9m#;1nfBOSjhMEb`E>YUj
r0e5-H}Rduk7V#T+sv1F%vCPaB6Y`NecWsA-rgTDHkwhgGtaMDTIeI_n2cK{)synhRWvjkJ2sTeZ
7c<SbqON(n4qnW6uHF`oQ^<B;6tedYT=M}u+$j^J8gUp6SS)xh+zmmVMhsu7N3*=smI!$fV6lJZ4
wYOOW=r;_k=}d%OF%VLMU|>ZkU!`abp|bRiD^$H5dV9U7b-isa`E_$CRFwB2DjT^~@g1H}?(}79<
G?iXA}O0pjq*PBX~XsG=%$8f`5CgV3^(JAW513C5;|9xj41>pcK6TZk$t%|=GUAkUx@$y)xi2m_u
?b@ZXEuPMxcmE`9)`=Xhx32x=ZDko9ZnOCXG%foVQq8%^AS_U-==+dZI^K8mkI`>MIdnIN#1m|s>
Qc%s8*#)mK_XLw0PE?U9%>g@;J&as1d?sFJPoYC=<zl|UXvw!sQKxELrlYa#Rfr-yQ676W6}qJq*
s5#|zgib3JN9I&KWATWpZZ!T52uJ)(Dx&hZ~H*E`N+kY)>lh)oDSQM3)iw>xr$KAEFLc@db(>mij
LFqtestjXs@x1r$j**tsEq2x)*G5sP>uV{=7=jui17AVf8(%1GEl1hM1N11lA>rd*ZBJ%d6_<TKM
u_<XT#C2g}wzmP=leUc&&?lbQ?<{hQpjkRdeL=4a_|%U`PIl?#6<6;`zjhPt&|MU%$rR_V*0txD<
oW~b;9O*Wr6>L=6<$7(WLh6^!t!f((eGE}6?Jbd2D^H!d}$nzIcUmD+sSBqp@j1WGytcW!xdnp1t
nK5f5T!uw^E1UF$1wx&B*XagG?K~=dLiY!>+Q1O!a*y;WiZB(>S0m<C(V=A@Xk58>h?eTQT^2#en
u<PAQ{v}<eJEPRQ=zMP76r`3&__Hg$c%+}w-^+IRq$(#njma%WN`jk7qr4E-?HJ~IfMn*HCm+UCc
CvsE`|-C=Aj7oZ;@)-4H`ijT4v&wV|k2;SGj`-8zef+Jg&WY_vY!de+2Jd8H_=BpG{)XU!D4xzh8
yZPvimP;rw#l)01DHzI*=9li+`JiNd1dJwxT*zYhMR-=rg@&H@YS5<r~yXW$}?yks7ZTAuvw`2At
CSt1Iw6~y+29cAI~yl2~~6$s_o>-Wrh&WaCWDP0X<K5by0Utf4K11-EFn_hXLLbK90P~hnWYGA@C
Fjkc3Ch&fJ{oXSf0MI?lSN-$l)w)E!^tMPE*=Awc>%4t`nx82R5Fe;xb%`e8eI0Ki=I^%<o<Pq*-
I@5Ps@<c);fw6n@tnH~XK}d58Y7IwK@mAxp7WvIrzjn2h96Ntlu}2m&%WVk{-Ja8)Z=VSUN}FGQI
=t3zybd{N)q)6gQ1%UCzPfmybiZ!TUS^~IA3Z&lO-;s=LyWb@7fa>B-4u`j@h)pTr1G!J8D+Y1|V
}C;rSz=nha|jNZk}?lfnrNdNyu+ZQQb4;19fB`b^8jbkF|t?8V7jW6#OBBX;m-(8sBidi}n#NCqf
KsHYlO*!he@nMI2<rpy@5aGY|mdj{vgFjE56tLX7XoXi7QR~DJE8_Jh_r{pREw%rhsp^rtL;i<0F
cCS*f<>CqyUPhcfp`vs=hp+i@7FBJcStA_2KK<3jVLr4-e1(^xT2QM7&vXR;G+3pTt>YxQuXfB5=
@@~zKuoGY<few`F<atBivlqkmD<YY;`!DxG_$;{C@cX(W;JG=6^{vDK>v+vhao*Xlb|3I_6p410S
jPBLNajo0gFL61ZrbJJMJUP!$8MBt~D$$XG_x}UCr?+t}LAA9w*KzwIxAD$`*9ZYBlREy`Z6h<cV
Qn5Y;J&n@z{#{ALF<JD7|$CJrgHb5Qvix8h7&GiPk~uK$hoHW~pC71mU9Zs*iPIultH-I!cjZq^M
Kzt&p=0<vaS*O;6fXY+Wbl-}G0W*x7KRM~LgPyumBzZDwFD7eI$+0onIV(<m40jXn}*epIR((6S@
{|{Y>!nub#&t`?ed@gF?kT^eIsy-3((|!VJiK}L}j6u(%)|@x0JpNnW*KbXEm1|mQ5S<+j6f=rd+
_C42A?BDh;ay~L;21ku!+@~@!Kg?e8KlbjxEMy5jEw|Hr!jNlqcz=wL6IxF@rY-3RS6SCPZBpM4b
?dV$vKmAvdm26HqOW8yVq_o3dgy*xS(2WVO1%F3bDi16ah5Lffg!OO~*~|Dotoy`K2B$(nY}43!l
cp;M7y-!?GCD-4FR7NU9t7l+mJRuX$CAIYHwi_hY#!bxqjsxJ(NkiFhiJM*EG6GAv(-s*1xuMszU
?i0x=!eP+i>O=IiCEA4S9C`#Tt3H>l}eeCFM#T+nQu8H=ma!2-!8w84curk1Sti~wn)dVjk<7^$I
pYmWy%ng{g2<O-^O*ma|!X(*pRy+088k<=!BslWD=WF9>4ac-ioM5V~DTi{=!klR+G(namh6KVxU
p*A~&*^Lj<BXNN@OFWtUOI6)3!S&}wUK!*#_wpGylom|ky5}#8h{4Rh6^O#i;J<s3Ox*^2-C{0Jg
C4qPgBk&rZGOy4?H9uxaNFylvNHeCHfx?ae*)GCBfc3Nh%ecp)=p%ImKgX)NOoZtc3qRakmQAP3!
LHqeJhi;SxV;vu9h58At7u!sSti8+IQHR=4M?DEwpy7AurFT+{58!usU9F@8SlOq{OME+Ze#c*v8
SpV&I1GTKc&GEIzyV(gSMzAJD^9pd-e9}AsXAn4+u@=+D%n&?~O@MJn7+xhFM#SU16A|;TMJ}2M8
#B_@-b9}Z=mrL4`BGi(0{lU<i8%|?*b4ibg&expJ5CazwHNtvEPrSW3SrEMqo_iJ%3hQ>nuq4UDH
Cn+2wiSUxZq<L+->rZo5N?w7amOfXEt=vk<7y~aCKavp>_<XE-F}Do$}q~rW4{NoMvJ0b=yqk3CK
Dn}e@kH(1DzWBksnWNLZXT7PMnY)5}czdLQ1|CGj-8Hh?=j6o<x9dwM)&@&C%+K5qL6XIx9R6(^=
aN$k7sQj13D)eZnI+U=Txg#OM@^cz3Lq%=&L6BWe%u&5OGYFw0A`u!ceuYvL~f1=2fQ+I70ad}Sp
oC(EVahNG-dG!ypgc0T%|)U)HAR27pLC`2mIF$qLyVyBd0ny4vK`95*wpsv*o@}GuRE#28l5=xao
=LTirF1ILqWr1c1ynZjZ3g-)HDc+UVz`mMASA0G7TY$3=F9gK6NcgtZ8Am5H!cgU~$mSua3guRoT
j1DDi>6rVX*Sbl*)HpP?q}g=5EQZiPZ~&hxn)+~WV5(!VWpXFP)<2Jt#q+xqH_{quWE0y5L<~mI!
5Q?&z4EddZMBpr6TNFd4p;;oxO%SR&)BUr#0v3!hu68vZPyXpG9(O6{d5uZV}7*1Pt&?U1{!UmE)
mSw0hsLQ1zr*i1<`Iq3u!hes+~rqbiwER&Sq%o@>xd*i$suY{3;4nGdqJyo-rtdFNIItK0Retq%7
KJ*;DZIS^scc@8%ilAPGy77wZGXyHXMo8^YvA8cUe^0zHvY+$d5(WM8EM|7Cw9M1VA@ilCiXo(24
<2r_rr6`9VroOk-W|VACWSJ^6SPko0jHTB3)pLx_ISW|~RjNjuiK+4)o&#sh3KOZ}mUnHUYr6mwa
`)Elz0Wi*7cseAX;qud7ZTC4Rd1<DyJ~Ykka~d4q3$p{a{wC~*DAQInD^H=YXW*l16aqTwet4hOi
mc~Rs&mgknb@Qy;<1D(7JArHg`Hha!=ouw5gU4vvhM#8oEplfh)|jE*gXwmP^B73J8}_*s(FUxoF
!c3^|!3T*p~tWj!E4ejYCUe7{w7bXGV6lJ$x7iP;oZnI-B}Wt9<PHX!Y9<yfJZ^cjy;1dHanLZef
`)Es8HDCjV(mUggWc`U~;Wk^+RP&<@Lon&7UeKa<76^%|Qm?lgq4Y@AMgG~Z<4ZgD#?yny}L2IzX
ld$@bQ&GR7ZbjH<t|O*l+&z-f<dn8kwl%>b97DD$9LhIAp_xhG&|$aN+#AgLYBN7ygfMeuK;5IBt
6uN0G95@GASdP^;M;+KB;Ft}{tB2F0H|i&V4XWadGzgn0n5hVqy
