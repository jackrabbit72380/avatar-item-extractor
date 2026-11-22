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
rem  It asks one thing: which rig. The Halo rig is the default after 15
rem  seconds, so leaving it alone needs no input.
rem     1 Halo rig   2 NXE rig   3 Unrigged
rem
rem  No folder picker and no drag and drop.
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
rem Still one click: this picks the Halo rig by itself after 15 seconds, so a
rem double-click and a walk away needs no input at all.
set "PROFILE=halo"
echo.
echo   What should be written?
echo.
echo     1  Halo rig   item on the biped with the FP arms, as a .blend to open
                             and export from - plus .jms and .fbx
echo     2  NXE rig    item bound to the NXE skeleton - .blend, .fbx and .glb
echo     3  Unrigged   the model on its own, no skeleton - .blend and .fbx
echo.
set "PICK=1"
for /f "tokens=1" %%k in ('choice /c 123 /n /t 15 /d 1') do set "PICK=%%k"
if "%PICK%"=="2" set "PROFILE=nxe"
if "%PICK%"=="3" set "PROFILE=unrigged"
echo   Writing: %PROFILE%
echo.
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%" --profile %PROFILE%
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


# The three things the tool can make, and what each one writes:
#   halo      the item on Halo's biped with the FP arms loaded, as a .blend to
#             open and export from, plus .jms and .fbx
#   nxe       the item bound to the NXE skeleton the package ships against
#   unrigged  the model on its own, no skeleton
# halo needs Halo's two rig files; the other two need only Blender.
PROFILES = {
    "halo":     {"sets": ("halo",),                   "biped": True,  "strict": True},
    "nxe":      {"sets": ("nxe",),                    "biped": False, "strict": False},
    "unrigged": {"sets": ("unrigged",),               "biped": False, "strict": False},
    "all":      {"sets": ("halo", "nxe", "unrigged"), "biped": True,  "strict": False},
}


def missing_rigged(out, sets, biped):
    """What a pass that reports success should have left behind, and did not.

    Blender exits 0 when a pass quietly does nothing, so its exit status alone
    cannot be trusted. The files are the evidence, and each option asks for a
    different set of them.
    """
    stems = []
    if os.path.isdir(out):
        stems = sorted(os.path.splitext(name)[0] for name in os.listdir(out)
                       if name.lower().endswith(".obj"))
    if not stems:
        return []
    absent = []
    for stem in stems:
        if "halo" in sets and biped:
            for kind in ("blend", "fbx"):
                name = "%s.%s" % (stem, kind)
                if not os.path.exists(os.path.join(out, name)):
                    absent.append(name)
        if "nxe" in sets:
            for kind in ("fbx", "glb", "blend"):
                name = "%s - NXE.%s" % (stem, kind)
                if not os.path.exists(os.path.join(out, name)):
                    absent.append(name)
        if "unrigged" in sets:
            for kind in ("blend", "fbx"):
                name = "%s - unrigged.%s" % (stem, kind)
                if not os.path.exists(os.path.join(out, name)):
                    absent.append(name)
    return absent


def rig(cache, bat_dir, out, inside=False, profile="all"):
    """One rigging pass over everything that was just extracted."""
    rig_dir = os.path.join(bat_dir, "rig")
    blends = [os.path.join(rig_dir, name) for name in RIGS]
    missing = [name for name, path in zip(RIGS, blends) if not os.path.exists(path)]
    plan = PROFILES.get(profile) or PROFILES["all"]
    sets = plan["sets"]
    # The biped needs Halo's two rig files, so anything that wants it without
    # them falls back to what needs nothing but Blender.
    biped = plan["biped"] and not missing
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
    if plan["strict"] and missing:
        # The Halo rig is the whole point of that option: without its two files
        # it cannot be made, so say so rather than quietly writing something
        # else and calling it done.
        print("")
        print("   The Halo rig needs Halo's two .blend files in:")
        print("      %s" % rig_dir)
        for name in missing:
            print("      %s" % name)
        print("")
        print("   Copy them there and run this file again, or pick the NXE rig")
        print("   or Unrigged, which need nothing but Blender.")
        write_reason(out, ["The Halo rig needs Halo's two .blend files in %s" % rig_dir]
                     + ["  %s" % name for name in missing])
        return 6
    extra = []
    if plan["biped"] and missing:
        print("")
        print("   %s not found in %s" % (", ".join(missing), rig_dir))
        print("   Making the NXE and unrigged copies only - put Halo's two rig")
        print("   files there for the biped, arms and JMS as well.")
        sets = tuple(name for name in sets if name != "halo")
    elif biped:
        extra = ["--rig", blends[0], "--fp", blends[1]]
    # Straight into the item's folder, so everything it makes sits together.
    target = out
    print("")
    print("   Rigging every item...")
    # Blender exits 0 even when the script raises, unless it is told which code
    # to use. Without this flag the status below is always 0, so a crashed pass
    # is reported as a clean one and the player gets no .fbx and no reason.
    shape = ["--sets", ",".join(sets)]
    result = subprocess.run([blender, "-b", "--factory-startup",
                             "--python-exit-code", "1", "--python",
                             os.path.join(cache, "rig_items.py"), "--",
                             "--items", out, "--out", target] + shape + extra,
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
    # A clean exit is not proof that anything was written: Blender exits 0 when
    # a pass quietly does nothing, which looks exactly like a run that worked.
    absent = missing_rigged(target, sets, biped)
    if absent:
        print("")
        print("   The rigging pass finished but did not write:")
        for name in absent[:10]:
            print("      %s" % name)
        print("   The extracted files are fine and are in %s" % out)
        print("   Blender's own account is in blender.log there.")
        if os.path.isdir(target):
            with open(os.path.join(target, "blender.log"), "a", encoding="utf-8") as handle:
                handle.write("\nThe pass exited 0 but did not write:\n")
                for name in absent:
                    handle.write("  %s\n" % name)
        return 7
    print("")
    print("   Rigged files are in %s" % target)
    return 0


def main():
    bat, cache = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    # --profile belongs to the .bat, not to the extractor: take it out here so
    # the extractor's own argument parser never sees it.
    profile = "all"
    kept = []
    index = 0
    while index < len(rest):
        if rest[index] == "--profile" and index + 1 < len(rest):
            profile = rest[index + 1]
            index += 2
        else:
            kept.append(rest[index])
            index += 1
    rest = kept
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
        return rig(cache, bat_dir, out,
                   inside=os.path.abspath(out) != os.path.abspath(asked),
                   profile=profile)
    return result


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-ri}3wzr}vMBghF!Fi=L?lg84=ar2yRt1OIuk$Eb~4G4bQzF@B*Y}ZAwWrVCik~*y}HreXpnRs^
X>iiI*LRB{j9F8uBxubuRHN=T*iyxEGcd}^VQBE*m>}`N6TXIXq0A;lI%8^ugaS|+q=jvcJRL!$v
B@R0apuV@OfGU`LYc1tKftlo)kq=zKzEpJ7qo&(yYvbH_!g70}W&!Zqg!vpYkRNW@%BR*>x~YvyZ
`5zMzMDFM``Nxf{@zIkXWJWxhy?Ac@B}L5wZK?;yU&ehNN(^X}365AU7@<2)<lG)or2-A!I3!7Ch
8Fq-C2JxnLTUW9$d!T1JB;W)qh?;qRad^U%Mi)3<<QPCo}$)^(>Q5=lYvW>kblYjsdyw1xTe07s7
66kL^odlyKxL#5N!Ns!Q?d=C?3G<jv^E;a0MFx|a#buDr=F?=BWF?dwtprHH$#M|~;dl|3N%4rG+
2#sG3tB3Y=@krQo-Yux7ukK1rSTU<@G)6r$@I~EJd;XA)C%s>@`fM=6ALD^KnnnTF#U87Yf6w0;G
e8yU@v*lrl|%`JgfH<UNX>M#na?jKEcxY=$BvyUpw#tn|_{WSLtE~vx~0*z(q+zDQ?pF9G+p@17l
z?JA6$GXD-wnrh+fy3>HN9wn~%fqzHPwy~n|AvMAFr;KHMz-#^?B%0(Jy*Hd^9zD#DSMz6ou#}fM
o`w`9jZC<2hnr8*9+bkhe1<*V@d;KCPU~ow*$Z|$1z%}R{m-#BaUM`YBHS1Xt7x1LG$a<Z}Uj^|r
hf?=JxSRv{d!2)xJX*DaZU@H7-#*cFf>Hbt8wK>ZPH$njd6oe7WF?^fY;=(U3IJLGRN@R#54!6F9
{@xQmvOvUq)=&|EZPWx<Q`rm&}s@pMQC6TcS(AEgNRe)7a4+A!zu=Ro#zFk9<9sAWSW$D7KF3}+{
r-{0HRJ7@m)}+v!oLs7R*Ld+6@<(hKuZa9B%^1ngm&r!1Cxecj052Wl$85@+O5X3mXr?YwUrG3~P
T)TRxVt5g7@}d=diylY7GYt3^JuHj98VK}eOfwEtYBWtn8bZ9H98bCuP`;tEAHu<~rW!rct}Y|0g
;afy(+$Yj4`weNr6cQ-L?!mDWxdlKOf&!PA#S-{|-8lZSgP+=fsNs4gkC_;$?glXec;>9(gw|?+T
kymeF%iriPd7(cR<zhK5tFNoVXcD$IetUoR&Fhm7-@iK@zCZi#)8IJh-uL#q7umD#-aP-u@Y~aq7
pL#kt6m=<25A50pH<<bZnul=aQW9KuTI~?^Iw@>bO*u3&RGV~O(z#SEq>U;hbJ(M7{RO`_wn(E<i
3Pmq95+zL)zr}(LO$Ue-qD>H-Mvy6bOQTcR=q1m-N#^>JW+0tE7x4fDhkiP_=;GlWJIxvDEV=oEE
d^`7~dAh+&uLw@0-$ez02j4PkJRji*5DaML3pPA1{${WzK9G^2q~P<YQp9{?fzWB>4w!8K0eS=IN
mw0uvGq(erf@7_Oa1BnI7ign;M()S#I0GqlbqRB_9Y)?5xfZ$%isR(qZQ(+`F3eSV#FwN3(I1KTi
X$1%pHA(!3PdoS!umS%#Z}O`vJQM(foEJs<DH*~b3wQ@qDx`LUFM}hq@9|AC{wN)1%Ndn7J5R5yU
Uqe%;HlG#Q3?Mo;uMd6y?z%v2rmTGVwoX@dpHTgUHAn&z{5#&u@gKDLZho{I4!56C^9F2E3kh2#)
uF1H;xk9gF}3xP60UFu=2%D<banUr~9nl!qK#xx(jlXUOA8Sx*3zM-cA!LubQu304WC=O0S;+Rj{
W6MFE$Fh>1{HdU%K{Zk8&Ma32HHmxV_`+pN^0h9kT9EG|Am@vs*>c|vs~sMNE|5Y<<6K}0*3&YwO
F_Ac?a(TlSL46c7e57g7&xv>a)Be2=U8IrrlG!pw20j2GGqp;U~XQ8$a+KU8;XeMKH(QddrqT&ku
T)cw?I@*YD%cH<WxuZJ9$v9}dgz;HaA5HI&Mq&=5R<C#HskqnQTyd{oub6r&-YP7pYB_D*0{SpA!
CM5>Ev&gb=tTj@Fu*g_`#Rij1h(C07CFm+Y(&*Zm?8Q`k+U+lh&fastB<%gnyWP+BUYiaBqjzH_{
kL<YwD?bc1F)kFh$XM_tNYqp4`USIPuNbq(4zJHe0Pt)9Y+l=EDs50@{VO@!O|KXp{ZN5diRiJ@$
^F8~thLaFGC)I0Z_-D5`__hhz+b=X?FiK98AaZ2xN+XC=IyU~yn}Msa~0D2Ti*kQDFZ>pY96unft
(Mf`hw59}}=NwD$Cn_}~^%<Mr8VASt$0o>;j4_YqO(MaMh4-RX1ziq+Qwgo?JQxGNt;xdfZ?O)Nc
!{#ch&#&@n+bY15mN5^i2GK8rey8g#ziKESLIn^y_c~o<cEUsW_T`r#2_E>n{nXUVo>|e$Z`3j30
SSvD#smZgmR^=w0sAkR475<h2Qcice?e!6mhk5zX%Eci{)O^!x6|qWPeRjnuM@n7hT5=+6BYyi1t
($x0!@$rYqcU3Nf2sTc^uCYvptl!NovO9h6rO^tY)(WgfmnR!8l^#$adS^&f{J$`Z~zxN!Avf$TS
^&QJBq5@^SI#<(qe}PCmTv%q9TzJrvx54<;TM54q)(rA1`G^sq(%nTb*`7|o$p0w)EPVfO+jt>6Y
=pD*&sa?CByKroHR<rMWPs=9;Jp^Nj8=4H)|K&Op?V5{}5tbDDkYOQ=)-^wRnE1znuz+zQcF7#m6
-U43+E4%zBtNbUs{3j^?$vPZYK-GKBNyyFYBFAU$B(oj6&wH!Sd%MqjsCsYp8B(WF@Hgn;6Mggy;
2sA6d(ZCpzINJ%RJg^k;y<4vQ-b^fnaPH;;~Ab2%(~8}OVm1DrT59CO?$1vJ?eYg1ELj(%tCdKU&
gSgwL`;VsY!gWS!xk@sP|)O%0u=YEOX=#D#lY;TTY=O7u`xoVwhEjH6NluJOcR+>J#g_CCMb<`nC
%-89AeKx5%yLR0tls+#K>M8qW2J3Sb?!P*<Qm2?FzVc@sv>ykfPGyXMlFEaRWT5-H_4YIxv31Srx
;ei)j{0>;qiO0(YUw~^0l-;j<1CX9+-R<93&u+q8nt^rPuKcJi)X+8A`PAE>N!FZY@C&=2tqRi(7
k#yGMBPgdyj0#oQL&;rG0?v@el9VE(CFJ%<)<FetM!JB4I5r;P*HkQ^-cnR#veLT9`HDh1PN!3)z
3!OP=Fj7sW%d#Iu=7iPfE`qFx2r2*VOle}bxqw9Lv>;x0RqnhHb&!$`yZm-l-T_<V)(I{mUI`@Gy
y>HY6Gy47kh>MS?O}xQq@6E6ngSfVBx&;@8=2`^bJ5!2EbuhLMUk%U;&LS#eH;QSgC9hh7E9uOsd
3in#K1ae$=G_{JOXgG}yE(;u2R75i4FS;#Fu=an~31+D&T(Xj_BORx3fZP^b3kzT@mf(RvItM&aA
bs?%0rD19UA6g`&_4(jl@gwCkb^>7i&Lpu(S#XnCf!`lf(djP>lL#86(XnA#&ENt>~N^B?<7yvOS
QTL0~C`^ISBw4vwF~6g}(CXn1&*YwQHO=EmC65u#K%cne)Ez%cc_in9eSi+Uy4d;Y!#D3Pc5D?4Z
WSyR1y2H7J-_jYD{fG=&yAYs%R`~Qofa?k$jom0`vD-K9_!y|tOQVVto8osA}p})RE=}>CN72~)8
j>s8W6WHxIazHa+(ZLOo%g8;=nACP7JCwI`8)lnrXk;lQ*><`-hh}VS6-mNcS`}j7rCr#?qrACgM
|70K5V2B6s)+dLOcuu&#gM7qES*X7CJ0^+jku(y*lCN6na9SFqVNpkaJ==?z!f>ox$RuVmhQfm*&
}*ekp|7dwP6)>2UoRF_{X{KrPkF>VJ&uEGSj4oIe=>X>v6LbEqH0tuhZ-8C8F73DD+6?E{N8#3V`
v~bCwKocn;0>Ic$NHrDYn_H@ysI_UXil_aG$kaP<6wAKu%+`Hf_fbA^yRX{yo@54atJh^-##6cA;
l{r-#$J^Z`l$Aw3utQQvPJ`?7Rg*xWb<VWp%AMX3T6jvGGrWG`uJy@XjPLiiF`|qJ@P_@caW|bS!
Wt_@~0hU#7L^s3~!ZDD@qs3p?P`4=g-;c>1puz0PldZc(Ljo2JNSO3*FLoGQGn#>Jh*H0b9FGoTC
e71&h^2Q5qJ5?xFrJm%TzLm3|BF+B2rDA>UU$4SL;(iuYb}nHefMivk5E-PGR8mzqpeZ8$VSbkjJ
RFRNBayM|h>c7NaB2K3z63<K?AC(W(^C9rBWJgCakQ-!iP(|BVyLu!WIs_rA0b$_3g4l=w@j|u4Z
fiN~&8DH{M_mDSM$bVc}lNaSpmIP9qQF9RN?U9(I$Ypq+WO)HXOgX+mlt+6Dyc=FkflWa<XP(}}#
I%4!b-ROLn%@P7yeNnibYCk*M<GD5AH4YSL$5_P0r>GCY6Umx^$k!ERY$OZ4*|qdluVC<qjs9Ldx
tQeyLe7*vrGjfomGB<e|JE8BC=LN)0JiKPz(p|dnf&FD_HLJSxV=RH)N&4pW`WP_Lxng=n5Mjawj
l{MLbLBk+9VGJrEWS3tmm*>w+*A!H~@6<tiwqc^Nq!9nlHok=d?hi1G~n^X{eKv;__GHS7wRnoNg
#SR;F(=%tWiUr=yJw*W(#9sPlc(_C7?aGfA$x7Sk_Ts(2umU%u6876-x9z&gS0daoDk&YZ5*CMo1
qhTW=)~93>nccuXF-88NGg50!j$ps&Rw8?={d%#($Ov2~0=xw)Kz-nMf#byv_l1wtszEgZ4OL?x*
(b-vj_wl67%;uqp~>M>`an-;Iq4C7!e?aC08jAmZ`IBoF0MxhhX>)U+Q7&*g||c$dp1$L)^83X3w
w}LzqN`g9x+_dbz>C#JAjW+vk&MRUgN_)J-o(;`}lBFl^k(NgZ{84VmP@kLl*8WoP?9`zC7Tad;D
Qhv8!Uf2^1j+pFM}^z)^xk0lz_4Wsdrh5Zbvzj188+xEuu}?Y7WH69iwjlq-R2n^@<Km?UM(*?fh
1mTYd}8xFEg&$D?4_hu1>D3<rs@L~4yopo_70tghQ@hAi%CJ-Lt7GViZKrty-^W@kmj&d77!(v~t
0r(AAT%a*h*oGea(fObi3<mAqrSV)EVdmr*C?B?mFy^yH>>Ne_wGk>kL*7QaxO|Tu1^cj?LM-$nl
NqkS0JXow;-fqM>zOwin&CFY5>%W9Wr=_=CzJrOWNp6C8XPW2bu;)sJSV<M4}cnP>qd;uFQZDcF<
PM#V-aW935?ie&gt#F@%FB!W52p0J_D~1U=F)bJhCUDH9pgiyguioogmEw6}zlyop2>Q`lc9;pSZ
{TcL>b^6^ALQFTKmCUPa879EM$fL#6)U2-~Q{C{G*lbbf=B@|^p>td~IHv>QBym!45qO#pX#9)^!
$K~jWKjND3!A9{pCj|tpq1#Ljz$C0Ny#L+D}I%w+Xz|+w|bP0vdVTS#K15cmh9Hj~b+0meP=oDxe
kOJImV7VHXrn|1ME-a7ze%zJyheEjiNKVyPzyPGNN6s3Kdq$PMU1iT-C7s+iVGY*W-+(o90OK5cR
fo^G3&r)9o?ASgCM8)~ou7X>mnCQg@VUpI{W}DS{TR`1>_a<gRLNB5A&Qvu?)gVt=XnqQ5-#i!E_
|$TVUH03yN$MJRkcX1|DIMGaHp}Os+0a78#=&Qe%#X7?A)M<`;ljWROo&~AtLawu5%=h`#Ac0e<6
@15=43#<avk~2uuR4S{5NYvUlmPN}4g;XkwO)yRBg;W>4qz0k%+!AHnWXpZf5LnmpI?W4Ncs@%XY
~AgFvE>4^e|F}l~YM%6Pl?uz5*1I6MD=#ahi@kFu#e;;S`h!`SZh2DMh>_kZ>3y`wns}kfi_{7c@
cy<%JqeU{b!RU-Y@LDW0G&9HRD&QC1lFLO)T_`Cra2^ATFpe`^gJqGh@h-Aj+?bd*^WEmx@)o+CB
_*0nu(VeY$IDAZY61M@5p`UN#bK{(?rRIijp55&&X=m$FSU?UXSU{Xx+tvM6S_%q3IP2c^e;slb>
71-Zi${*qHCA1Bor$CSMhCIFkyUCR^!49durroXs8C)MYSUTeN!X2|8qPU^N{Ms>5nmG$k`z^!M{
Ex$<K;mX=K9w4-d924~7uio(F5@vet8FRbLG}81rAqOEK%!$ayi>r3&s{Zq08gPU|mWwC1=TA;7s
6Q4{LRpTKIB%lR}3x97Ja-FdWa+go#8jcsqob~)Xx<-I;<8ezqJMZbsnA_ZB+YIv!^DtLNa*Ltn7
LC{1oN1}+Wvu5k}vwn!w1{2iCzun_dsk1eV8(y2F*)sXxipvatKbILbP*=Lwz%|+p=vdot=0@Xk5
aU^ocl&ZSQ{T~ALkHwN)l~qKBRmj27E<OVfOt#ChE0_=g6X3HgMB^FVoQbX?f`zj`agqVu=byn{*
8M6C2&$o!Ef`|>b~C5?6X!M{U?2zZ_(mIx276jU6K>GLvF?FN*j|xpPKZrx(@rbw^!$0s}qc`0GO
9-xByTuf1moFMUX#B`OmFs)qi>wXoWwXIJnQ4Nt7=#MEO=}`r!f2oSbqq#uG-7XdSQ^`4mV1uzPz
*J5;N-844H170?CNwOw5oY<WB2UMkcy{O)x@?LGmo5NMG2%ouX5CU6IQQQ*p#T%jgm5>l}jt_Ye6
nLq-GjH?Ea-r%@Y*NCC~Z3W9#aN7#TQ+RFL@iLyj26-Ss4|@{!f_DTu*h4@hu3@J|V!Gc$s{jIVa
Hp)CaAP4wrfsIl2=|22Fn^?24h0(OV>70C{@nr&<TShH*bGRTzJSJ7$%v$4_#oRqLwD{aAR>0io(
Mn^xb=2CnJ5ELx^j{>vB`8nUVrGOKTi{bJaKC|#*x6D$2UpxvGDJHx}Q)~cA-9=>uaG)wI8ZCd=+
%L4nd{io4AO}a#5|-#m-P+QDk)2xlZu%*?0#~ch117e_f0u+v;kkHo}%sNj8f0Ol_6RR`XHoIeMk
G+EkYseYbCg@Z5m4Y{yGRdWV4cW-inob`vrje9qDJ%ej{E(G(RiXka^Epg-vyUeL25qsuCOe2QO}
7>%Jz5gO=b|1L5)$d%N;X{>+i)W6a79hSIxC`;-#c!+&()AcQN1Lbe@Z7OeV*f1J6=c`t5UjZftN
_(^gg$)-N7~|le1ASdrA4lq=YvVvxD;{3vgNmv!ic8py#h?l|5h_0<9fyGp7?5d@7!0<l3d~9Syq
kKV@qDSx0Xy1bR9;@MducvF2OmWb_?|GROq<+-D!Rs|axf2HF#-nLnR>^i*u>@%>jz|dYp)&Bx`L
&(bgXk+UqPU^eaQl2+CbYCWY7l50M1j?#Z~08dU~|pzz~~wq<Y~>!by{8W!M=CUK+NBD25FUJy<m
y%TMNptmM*(cX?Pg1qPzFgyLjqdiyCruUT%<^umlb6k6VH*Gl7-Xhs>^(60dj>ucZKU{hI-FK}eK
;Z;5#c~LIW+6R~>jD53$^M8@BlRC4ssD3ZVkw#G+^gYQepF>(;t#&8ZKczPpQUqfqTnNnYJNQ1Cq
-DOaeGZEmurN@FVj&f*kv9kc43rTr&Q=^Jio8moLjciqx(a?-W*<A2g`|TYAYdFE?9sNcP{Mewu>
hWJHl>W&l#HA~Yr8}%cJAlNxFmIUxYtMF7fs`IN92Y?lF>`~XHCJxy1yOk#x^^0F;-E%hm&BEC#)
uz(U>1{_?=LXjRJM7XGR_dp)r`2231QBDzcF66^N(kMh43>2FVr<Fti#&(-F2Gqg|fhjSo5y0KRD
JH?s2vK^Tgf4p<L3z?eR2Qu31>5U#0*gmW!=^!*P3MH?YQIOd4S_^xAl^<p1;+%Oq5?stN>#=t=C
6O1M|v~fPomlY3MwKS8-n&i+!5)I1cs;K4&nMT6G+}&jDd%zZH<T&tYMG+sW`n|)@qtJmxmDnX~i
;)rIy0Hj7l1K-K`@S|5$dnEeWYdo+dM05Up;AXVf-fmOoFkqXZw5G{tvKk59iA7~;ZN8QP6D6c-`
}>=##U46^^b@kUm-ql^s3LD;w?o#SU*E#FF$*VRLPhies?F>bXXXHYVvVB-EbzNF2X1V1j;0=+Y%
|RJWC5AP8RVroa)_R5uxeono+PZEM<EIhea#c>uaZ7x{x+P?kEkDx0X?mgTZYsC-kAYpv_LW)M9z
-KKTXXT(}P<5S{as``$o+%;l+3AQXKB-r}z7APqy={|==}9+>|<`FSB2{jVPcFA;K;S1IW<*jI{Y
)(Kv5e834u<wAYO!O@<Ij%h_4;1>7x`>p-`zGh)qslr-w((EGHpWel*0!1^9Wry|yH;Y7(dbde2p
5{u-IVm#%KDIPFbcI0`u?N%-T`!Uq@a*w4uC=&G=F^l_xfI3o-8avI5Vi;Ev-*2@oz^`7uKg(L1Z
NzUtl&6`7^SZ^<$OGzF43&vk&2rK6lexa1`g?$B+iO2f=Rsii0UoP*%cVSi}|uN%aYm<3-W&Fc#}
E&%BK<sP_=}5c36!zuxlzVWh_CDO1Ckzya(13os1DWKax@YEFCX$)XJ!ch6TbmlX#%<D3^9KfOE&
W(qyz(6jpFWaLgroNp077_K0F^e3wYTF=*Kcn3^=BkQh!FLpI^1hyxs`W}v*IeGMY7f~dDhpk%U`
1B(v44^${cXE&pG8NI_t$fX_x#lMzG^2yZQ+3nrk!1|EtkP&JbbUVFXr_=59_Yu4a?W^D_9#@wo3
yl1#{jM#BU?VSZyRig<U0*cXjyX%bF0r26M((NsRaCXHCFd>CQT2Y_Kvi%LnxQ=D)YkDlDO4!Z1B
8MD117+F^lT~KRSbJeOvjJh2fai0Nq=8Gapx!FsQL)+tWKgzizKg(>aW)G2vV;aRlQAPd|Fi%Z5A
#KUI1C|&HRE{44u|&5$(%hZzI>ha^)JPfx9q*Sa{Fl-l1KEkOPQ=TU*f*mrNKFF^v>914<Mp6;J3
~hiC-}@^1P|?bbw*Z!ATdpjHAl4s*QqSDG^=23UQm6=UqjGW@AlKya6?lVm%&MT9_O5&2jvBGAVo
^3f>rn+D#4;Djs$OA5sV=MKh1YB?${bpA?Njto`6$?CS0L|4_CdjqVl)KYZ|LafCXg(j1;WR@>fX
d-#IMge9G%sfrdJ#9O7+%9A5g2cs=M{A96eLWi*c3JV2(_Tp8fK)^Ny*-zTDR3yXUhBXYS^5!-{~
G8pu!F|96iUUJn2{ai$$9tkTuV-J(WAdv#sysdPxCsZu-@?)aJH!Q`l#?23Mz+m)r`idwt}A`<q}
7OuBT`#!1Y9LmS#FUJM*pV{XR*G@gkjb^koX$ZmIg|bUzOAqJtfFCg}n@2-Wv^RN!A@NQQ;u7~@Y
*;*uh0=qkAJLu?i$N(mRn8oCYzSl)>m&mOCZO+y+EuTnS$hEdemkrRefwUFGWMOlP;_%7c@f!i_K
SycqPAjvz)I562UP|NbFeS{Z@z-?Xm?0zQs7(k0->7ciBcy;4!0Uj;hFy>>qpX5hmT9A(;H$Ey~$
&<V4IXcp!tKB8gKsH4bA8TBVBm<Tiqu7VsAYO7;hvWNIQ6{s~`;^>q^PmpA0EtQ<R1FvZYc!#T2j
d~d%*F`y6#H28`;5mp%ORl(q2zXmtcfl;d$%~kIClGA@87((d%RnurE^vFfAIHzAN*xHbsYTqTV0
&en9B`#MnkpF9o$E%9ja$?zkwI<>Jc4SJD2{AL@oX&_60SdOjHymwv_G}r=pe+jT&%Yh#?S_Fr!U
j=q=<QG6Gtr%czR5P<L={lEq1;zFeML2Ed-VayE&F3)QchT_-@(7D@_&+K`6@2j|Yjtr!1iWT$~?
LCoCIWEG4nmsJ)?6@nVj00bTRu<`1qQzXg9uof&!RuSGa!_BcGwEbT`T+SEBVTSWou$&Ju%&Sd@-
clwL%r?P1(NFE=+;SZmagvGRMnv{_S>EKRPx=u`wxE1GUgQOc2LIij055VgFtb%)?h9%`>}4cZg(
xS?gcWwKiXe;^GrAsX(Uk=yW8nLGOk$zT`6!b`CwRtLEJW&Wrv>Ih5Tip%mw}2J<Q33*$YY)Zov&
IHrLuAl7GUAEz{SqJ9i2#Q7SPlIszv@fpS*Rj0`z8^ZiX@dW93BU$hyNKRANg@vHEorPEqEfF(X$
74jw+l*GlzAS~{JWgtUd|;FFemx&JBtLmY3E!8c8+JRdrN1?H+CogJHEvX?d9IHKHzN-8;Drg1qi
!qsU#9I8=DWmsAScA62u5Pa`hCxHfe7<N$#SHCVRPFq3B5H1Y&gl>y$>J$)zcF=DHd*;~@lR?Xvc
Pth<PcK{5XN+#>eDB)<X3%0r8i~*#8v9d&au2DxF?5W}2C$708&$RQ*yv((k9Mo@zg1#n>a?N67)
p$-5@S<kj<<bKV)=<pyW7<7XoVlRY4~7-HNAzmxA5W?%a2w0u_`}y%RdOd&)U3NDOuD3s>HA<7uO
XE2J_`~%25*mZ59-ii8DnI(i$4249^GXCd1yBXdQlw9WF6`>n+a$KH#X9_w=$QA8>qJ{@&K@v%w*
3Jhe~*pUS>C$8wiwW{dH|@7I;-ahcV+GJP)dslrUzvv^K%$$^>j07Gt)R~)cA#lIG1$c1n`Uw#?j
rMNukxexmMAaWxgT~kEUUefOMy)(w9A010cZ-L&X0)1}*&&{BeA0YQ)?B-sldub6zflNgji2)wwq
hCTkGetJl=i4#S>y}o~9OF%%O)vimNCqr+R$}_EDhPF<)gq>%x>ZrlmT@_$h$hnBpMSnBfBqRY^L
LW>$0WnTOB8J5%(6W02c&Y9o<vR&W@LC@$W0$T<HSoOH{;!UK5tWgha66KOsAE8OoA7CFX)7XIYA
k*H_FR0pHW%r^%iSiO*xjRzPr(r#w&&;ht(mrA-IcI!2)emJmeTdZ<vZ4B7O`W6OXZ!(r;Ys%*yF
B9VsqKl~*2-9L2Y1I1rNMMVfhZ7;;^5%&*QZ72suK|G5}^J)F=0xK7kq98O3W@rF7$P<@8$!JeDi
#!CnLE0)9H(R3RXujZumum^V=JnS4^Rlk@qRgGA&k4ZwIVTp`FYEH5ZHZOKKV!LM(G+A>5@wi-)A
rYI67mV9xi+uJIyIUZ?00fV%ObX;bxMjL(fCma6h>tgKR+hIzB{_9%z-#@FH9bRBE0e58h2@%3fh
`Oo=H0X{f!r|}<x*A3XDnij(yFAa3}`4GCq~DG%aR2>k|0{*qgM*acdAc{JgEopg!m3BAvr`uLhM
pGZk?Yi+8b>^w$eqkB~fcQV{gr>>;$QHfL2mlNQN}?wnii?+K8yY^O%YG8VO^{tbqyQn*HZ+&z|k
r!f{4_$)?P<-IWi5_p?05ZNazBgDP91;&eHLcqzFlHE%3;rN~8_o5UGO0fcnNAyXb+7~tUHgN=nM
X&2-h)@+0`(bt7!7n!)tnFkuOjMHh*Ya>;e&~<}S&PzT(rv3QZxn8VzbP00~b09X|{3@Kf^Qd3<j
BQZ0IKafTT#x9d{()B*M#VoP^)u$5EuB_<9ZE0NAG52f6SD`NFv}et#E<IQ2Ua}XZL1l(y6F%L24
lRyjDoEEpwXlAtUQfeh7FEUmtmX5^C1#?4~KSA9R-MSVl)edMbP)2MI_S-)&P!GJlfActFD+!Gnp
O|amk9KOlH82<#(BKcm(dJ;^@l!Yw}o<do0qqk{2nOjggES&tXfVOfy0*P5A_=Frmhcm`T6ZF;p8
EAO~Tx<gUi5_*kQ6X6GL<o&)r+{=p(8Zbekf9I5iohqV=p-`V2?kDiUC(&=<LbEqJ3sf-MRwS*i?
!NfGD%5^OIjS3Sq3n660^%rDmDFr4yM6;~vv=h8$?2UuYWKt+QY_qux*`r{LRxFr#H2x?DpP^sDf
G;{fafMIH70zspj?5|MBhXt(?0g#Gr2+MyA`gG;DpBu$jH<3L68Yhf9_moPc03(P6dkx(IjzjIkE
4M}7sfYvUQi)rJf*11ckzl8l{0N=mx*GG!@Z0ACtd`6^(m5<q>-2`$$iXVclY{^WBhV9A_toKII3
FxeKEDu*UMy-XOK!Dx|FV(f(Vro8x_NnN`7gtb(EVoFx0nGXx}Mn8@{er-^4ZFw6jDrgZtnsH9}-
3kh1f*1~OE%;{$1%1qoI_F4$C#EZo+NO{luEdOYDgxPl;yWS(H!QAu7+eXVH=6Ac$%18A->|5ZW(
Zz<I`4|0;Cdj&q0p<4R#{t??pz}6cl2-id*DCG%}cuhFg{(faiF%UmfSPbHxxIOeJZ<%L}0&GiTk
h!>u?NTU9YWOx#hh~R#9SZwNVCjTvj(XZe$?pq})Ir+9Xc*^R!#Pr1L-xC09j@zvE*g$iE9d(vg8
<IZJr(tBzY5!7HB18GF*V4BNtot!pg#c>I;sZ+=V}Ou{lVHKA2c3qcgC?rxbpd64+HAS7x=6^Osj
w`6<E5^6NBc-F{V}Jq%pv=!Kg`b+~22+8EoM7l@mJ20f5)^l7&2h1GT0=@YTTn3ZK8a^ah!+L#VI
_IjCk<Impup*j$O+ThP&`VCy9M(6Wu1q<O>bd<G{~SY<O_6r|fx`Kdc6i|Zw35O_;(Lc^ltxFYD8
$}>!P-!z%xn?1VA(<dDF(1|CLVJuApB6GrdMCL{EuVuOr>v!~`pU$BpPa^t_EmH5;WIUGPGE8*}X
x~5SFV<E9K)5^CohoNs$TSVv%vpkZb<wRv8^@E6e&LYK)B~N>%)cVckko8!VL7LKk#xbGT*b?2sd
TPzIH8<z9Lo2LofZH2w9aHePnXS@`GmY@nRhu4a7&~jRNil%A73h204MT21j>~dGoPkKS!2;vW$6
PNE{G;kSM&!vD=OPWrSEagKCl$!H&p?0QK7{M4a9?%71dG~J8DI>ie$b>X(kUR%C-QuIin@;p>ln
d+*f&@fw>&|{Yr@o#oGn!+%*51=IB{qUdik6+E?<1Q;8ZD-hoR574s&XXcx3=St82?-?5!12TNJ>
mpYeRTy?Vul}DkLC`TVTBp>;zn*&z?_a3(QfU9r!4-0Pb7-mCl9;;~`qx95-tPca7*uh9mPl`VE{
9@+~p4o`<zCoMkZe$s`idP0K;)sR6YGP!^huXX2V=KCmM1bI$UMpbNpo6mB3oM{{k#A(R>#jDy;}
mtR>#!w1#tL}HV9Bti?|zjkO2fjlcsz=Y>I{o}!vQ-rDm5gB81u!E)0;@0dGyt@0|E(#fjSw{ZgX
s<BBHHPUDm@FeRovHD8M8fBZCc4h3%1P{1sZL-2qhF08e!Xre3zp8ML@gU0<oDaJR@yqJ^ru$YUv
{aYR%Y4p|dE9OAh=9BN|*KBg}+sJjE==K^T#5ZO&29xFK4cOLxh(Xv=P8l~BzB)bjf6lHV|MLtT0
#Wj>H^y4VM5B3hb>e!}+*bXH|&*gZUUoR7t5TK2(NngVp_j9sKK-8nCFw%CL&*(EK+rI60De`HV!
}h$P#Eha~E$?!|MtBDBUy}HkmJ}AVQ0_E%-YD(QD4{+`6U&?jN_i}uES6a(_@@*^T8%>YMRxN3`P
mtknlBe<zA`YBnrv60qsbI1iv^$n6i8<@zn}7DFv%q-%yf#rKkSI2SbRDX4G$-jsjgV!XzObg-RV
U}z0Q&9lNCn0y~y)Y%{En0x>#aSL1PQn#iO<sRzW!zp$Zem_&N_><aZgRC_|le@FFQbf{??X^D!O
DMJISGo=7}s4NK{Q?pT(YvP3ySYkuGp$CM6=e2jTaN=Rj)na|lyS=<JpAzn{O7$3+Xc9A`~UZ#_$
oe_rVO3{t#5naL{WK?_jGI$ioscaw_NRg;#nI_f4i!7cNIYu4(SV-c=<Q{#|QuMuJE(D#S3k6<e(
268ppnFz6OLzehd=v*MzQ`!xE*AQj&Ox*+#yP1DpdDa8ryLIHB;ygt2oWYfqo(5Lig)P*&xoS$sf
8r6!g3-}UV@HTCT6TD<s+cLOqgv7Kc)AQ#TK;;v{NAnNKML|ElGk(LPl(n1B<pnCwOlrtV|27=J2
uxMwpc<wG)qX&kdll;V{8|7_(RCR9LhsMe@KP(c}lOOj48|g}R`u?)xt?ameR%>2i@Fj;0hZO8G^
}wR9>8olSY1^E}gveqY4bO8>|-GH|JBo%MJCC<rZ*Zi)6`OI6Y)S50j_;XTyO7i~o2r=%Z@OWFsr
+1Az<WPUNYfPbj2vY%ie44l>*wy~Fqfvf==|HaumeQYrv<$Qhxp-2w{)n77+bj{H(_VHY(TBN`tR
$QIFun(U=Pfs5`!L5$+jcO#Du7a}{|3(&#oF*7p^q6iIar>u8ITym9i&%yF8a<S0I)mN)y2^~EwK
%VtqN##e-X;>GO@}%0XpVtE@wqC;fYV?R@<3;ckUAr{8KqBRI0YoK_=bqGTYHi&q}6J_+GkvFof|
-}pJ}vd{z(SrvV;s*eH63(FX;laL}^-ZUm+X@BB)ZVw3ck}R&br<m{EOYHb@IK2jH8waC1D&NoZ$
6tqUQc1OW@pe(?=Ht2Jih3!U>U>cWhW_oYPaOORc<M2GnpV=QU`(d0dV@W*&8=#i_AI#p(0J%MwS
3}S+JtRg5RlzOn&Ioj<6uaVxRi%A<QmMaq6V5`%v*D13lEsauc=m$4(aWhRv`a7Axt1o$>KQ5{&#
m%xzr`1<d&sASnRi#hV@<n#``o-ywlyuQONO5pyA5LElPk;Py`uhFZo7eBrwESWRPe`$J7Hvj^y8
DyrjG*v+De+k7WDVG7Xwq^0GG_J!9A5`__ir)wI_)}aOTh^*f4}+u>;*3&uo0AWk7Lf$J&N`fC*f
8i)sN7wa0z<`?UbIsdHvz!?Dgrp;j5Ex&Yn{cag}7Wg;}SdKp-E#JNw~OKE6GB_ns#9{vT&=hp>@
w^1q_UG)abvNhBZ)hx64KeSeWJCa7GeC4agF!9j(m&_u1S>ABeXzuuib|LOU6r=4eKuemtOX~7Tq
6oU+%WgPbo^IY%zc9Fe0`EmH-^zDalVNiRPuL<t`P%$AxAOfE2)H6XiVvVUr2U8m;?pDI^Fa<&;(
O}V-GW;HYlghb6RLIH^!!a5&$8OsB>*7ivGYi(+#8Bm4{}r_+=rs+G4E+f4UYPk<w_+s+AoI(*7f
pE+t#e7S#-OgxY{)xqEp!O1q#BTZU@p))!|BQI18HQrGWzg@gJw-_V;ONMWJEb#EO5^j_|zBBMU8
cy&%<uilv3OFuCM^WiU(AVOi8G~4J@~u6LzuKB76(T&kSA|rB+DSdd{jn=Zt}DXqevDPC}sW%ghi
_FwQTZO>tlj4!vv8?v1gfSfbci1kZ^n`jF=shn4V*<N<X`cmAaNPr3uuB14sMgwFRNav4SF7{2mV
lH>xx`LybCU6nCJWJTdv)b>N6#GnS$Pr#cG#O(3iBvh{54}y<L!seuGsERgCAyM}Kh0Q_N!1B>?J
6Ql%HCaknk3tOZ_}Wh0Yd-+s!-0u6Z}Aj4n-y_HVqnhf4($XTxQp~1mGy0j*LUSzs<_=ENis)eN;
5@)31?;AD&g}wHNeMFO&h05r3I`um)U6fkBXjb6>>k&5uK$npbjuEi?Tq#h5TX{`zVq*`xx^xG8R
m-&0S$B?QvX9K;<D#lB~LxNsFOA<iolfBZcR^A_k3RY&z>#e2U!NAj`%|lB+6E4S5k6lB;tqseo4
iE}(@2_j=yDH2u09Hl=>AhyxQ-9gAkxEgQ7Q)eYd>)HMo`=J*{uS?$vZ94<p8ttBe@<~>o+`lu*w
vISgbJVWODTda669O0N*L)wEc)=g6pc)%fR&8*`{bwk?T$hsroo~yB;s41f>2uliIW_yuWfQX9Hh
^Ya|mZ)DTSVHOq&ydiH%{i(%<|w~dOV6ZuyWRK)_8Hzr4#`ukX*+iSU*QZ0WruZ0g|EKZYVh%Lf#
j$KR2Xe52!>=9S#<8==|}I7uqeAd6m;H&6KaaoH27}A$)_?PnKS`7P{Lt=-$c1DYA)6}pVic5=xZ
m7!HG1u>M2F2rKiV%=1qP6vwF7Yb<@iV|1}`34Paj+pwOiP7IE=toBozr`mbf;AeQ3%s8t)W=#>D
G>$>LG^iW67skk)Rg8cr^I^gk)=O9z$sA~j4=8Hz&f%e`^C*)L)C+T&LzI&~J?@(puGbiJUf7*=Y
r5IJU0SDp*8KaF+D#?n<B8r4Gw$YJpR+zg1W&f5$Hq~CA`WboW2G6N2QNg2FE@p1n;ul5jyr>k^V
w<Lw8z{WNakaR`u+ATm@EXHO(S&C#U6I|6YT#$)1M$)oBU%2e^qYHV!Ic%{w7PqhknbvPsotYLz2
T5Yc=>LGJTfVmBQaPMmk7BE(Jj$dDlc%)spPk}gJ*cMppz5EK#NgH?mxT`%hBo%(b#*kp?(6#fQ1
wlP}X^T_|n(1maa&f4ncjNy-ahO7et&EE|7zee8pZClwpNG_4KE{{^VwL@k>M1`m2PQ)Snf(NFN5
UnnT1-m5x;g)pMm9IoK&8l6$tVpR+9XInJFt^_^YG{ae@VLPw-#btL0e#;~d$Vw1zvF>d_e*^#iu
w|p?I*=N>a%n@%<$=;!lA>iZx49~mmuj2OAN&DsHuSdT{ZNx`42y5sRs-E3(7Wr}>_99vUaS?--$
@PS7zYM$0X)-QDJ`p_3hQu$<wH}wKSf#-p;LUt1Xrg)|P+QZicA}w=sJIF|jGXZ(H0Ds;HC|Ocz+
;n?B2v4uh%=ycu2!(sxU?-DmlR<wja?d-!|Rj}TwKu}H~XIMJFIU=;&6pMG0qz4ze7A-82Jp&Qo}
Y*_fYR(L+CZ{G!)p;h?q5!maR#B*SKadG9hRj#YSWq)#}t)%Vr*04TpK?t@zEBp~dtdjbmx!f{|N
rF$AC5=+O+)HRInva@fvplqf#Uw>eL654P#7iN_NC9u0O;Zz3oQ2i$ZTTmuyfmPM1m*SOzga2Gp0
Vh>xk{gJAEos?)_qw4>`9isb$zLZ&l!G|eRtor7N9DCX2EbLiWSVuo^;<s%P&|W}2US_0eoNSu;r
?I1&1>^?*$?Hs)=rBvUMORVgDHd&J+IMi2Qqx6diMDkY+3PnSh9^Iqd^mYWmlJ%-vQDnLX3&})c@
(g<M}X!Yz*uG_-@i{2G>b;_*El2PNQW<8=++{u>`vs?0puJ;S9_!rW!pg35`6Fe{=>`n1Y5Mbpqq
;iX*nhHY(WqeuT7g(Fn1{z9&D)r$28R%1f32HjZQKE0XA-3T5P(h!16E7-oO3s<R`L2Lqo0m{a%l
hWxYPfndZ2D-TR}iVyM6W@Uq=Ie0Iw0JPkz}`*8N*yVI(v-r-k0*1Y+uOPy~|PhOnjqPZ>XQmu-Z
01w+c93_}7)ukY>zyGd{L3hd9c%pldfWR^PPB};Sq%unbSWnp<VK?ZB^DFkkYQ*^N99|9hb^j70X
pWGzz3+DUml>&rN*xD%Yg=IxSpTxare7g5<d}m_qODilc!ybOLzN;}HY^d)J|&u31RZk-aT1+<2&
ouzs=Qf99IDNw%3HwsV>&MigL`c0yo`m8wo`RkNvg2L^TGb5R!(R{Uz-OnUsUlLgRq9}Ef?dQa~!
b%dnR*wX^3&snJ_I31{V<orQvdgfmQFaE(%fILF0u>$(yS-KZP5^qP!}Gcpw0CE4jhhU8Ig9veIA
hB^~Df#)SgmHeX)fkm(IOGm>geIh`CUJ2Rz4C;JJ!X%_dSurCT+ybYu$Ky`p!r>97D9wEJnI&0Dy
0?p}m*R3SeM4bl4=R@+;$R*gl-`h8wNF*#oXtuJ;xj!)c?*F1sTom~gqFj5AztTgchr7X1@U$BB@
Aq~2wi>52yjKmCg{oQ-V9HG>r4I&bJieU3!hQ-Hwb0%(K#Q9}tmb|tSU$|JLb`f4r-}FV#<G)P-z
d4l6gHAk^Kq9mfQxBX%$aHQaL7E&^)Tcces)hIi=-k4xFvIrIi<Y3N^w}5uR8Ut?d+k=1Fk+idIW
PmIl<&+vLE0RL7}TAEW5@^M;<jg3Dt8dp#n8HHekl9Cyp^@hJu@A_EDvnq-q1MyelKByAx3r-Wyo
Jf2&|8tya^4(}!wn5hk5l$|BF)ut%vLG2~$X3~Z5NMY<j;qrIZA+<^TF@Z^l-k(mmCQhBOi6W#m1
={iN0!c)3KQz<{IT%`s!>vF;d(`Ur#{?Rt~VpZEU%B{-#<(>!Hc+?)Vp3gvy#yHsHVw|S#p>AN!M
jA#<GZC}JeuZ!janPWBIe<F-rcB`iOX@$D>`qUa^mgkQ<`G2Mzpl1bbWkkZwHl*Bo5~VSAtJj1Z*
1=%wJoqQH<tzWzbl(a<utBsA3}DHlc)nKlLOlT2XtvmJG?W5FEaS86qbbKkkGnLs7_MTnwBkIH6P
U?Q6Nzf^AtBWjyYPHbqvylBqgc()eJnzhH&-UHDmwY#X?U56?w9<v0}HJ+rH>HY@Vj7D4qK$3xiR
LoO7ki%SM$*?bgK!rP%@Am#>=q)?m@PQ5Zoly(|!MKvdL|(NRUn<*VZ>HYFn=Os|)fPgYqnu$(mp
K`?Xd6@0u4wn2FL`8+D%1qrjq4&y597p`!x74$9bn-KIhykBkGyZ65h;R6d!L{-}Xww-}8BUdTVI
e|4kB>>=<ZHu{|K78}eMn!j(joDQY(H}9jb5%;!leZ=&EJj08m6ZYxq9;BZ7TlX;Vp!=0M#*)WWf
Wqe6k3aDs}aNwYf4N8Uec05Z-I3xhjWSOPFf5j3*1L^v&;&eucpd(UKoDe)ri_+nIY`@Jf4ulL7P
k<IDXr*?5Mb#I<g4JR;b=i#ClwuVT*+B$#U&1!U=5_`Nu?@#5`A0BFcFfm%Xl?8k+^BCqbW5`e}i
UWo1T%wH$t23@I8vdO)D?hz)Rkk<lqs5UF<5;ie_SgG;^;xY!w`*Lt5$#9t17E75_9_wkJ6PkWaZ
+Z^`Ln_6n($0NSM!;e)n_<XGZpwbHH4i716mOV!ranI^r)!WRcQ^}B`(|bn3FJO`MKrrDUiaMe7M
73y(SKPJ&!fwz9u1-(h7Bh^B>);_W@NuA!hr8J8HbA9+7@0~MGv_92YP3*oj{M27S3I+rZ&xTc>Y
F_Hgptr;w5X-?fk5W6#V8rMQ7RhhNwq-*SPfK9Q;OqW*Ob}Bpkci{O_zB|S=&@>0P3oGtzdI(0;h
hzK_C*_KWR#RqXyRpK}fHvHRSR5Wou8>YJ7}ER6Vj4a5m29%ZUlcuA4w-3KM}`dF~Rm#!Zsgd)UA
e9X^LF2V(YJLboPTq8I_dg(;L|^?Y~&(o^Us$AZbvSRq0E^*0kN!i(4VBZD66I1qb#Y&6xZjKHET
AP3?e3_SHozd_=xtTMc;n1b6}_>ns2%;)3V*Wc6_XDeC``DvK2Avpn??4V&;$oki#ub`oeiv=1TT
-^6!6&gtKDP#%R?yVzDj4f8fXQ!`UkZ)^QHATfXwIvUffWrFXqf3WVEyi)?0nT%sNI|^z%NP%49f
YD%-cf`xzHv7gl1g<)35G|B4)a8Jwc4!?UtXavADjVn=Y~<(C54=Ty7Ce<oG=PFbjjU`(U=rHz=p
)iZR0Lpb%JjZ(}-h3Eg?7Oa9LzA^|e^qQ0if{@huGIiMS?WT6}?L>WIM1MPyq6T8jOcvR<`&Dh(O
@ei9t+TNm0(*4y`7LQ>}`W5;4Q$y_0dJO)iXFt%sY__1BgQ|!_ED-Pd7h2-{3Ntt9a*<$&DIZ4bL
XiGMj?x2FNE!g-Z1!Zhti(uy%$sq{UO={$Zaxh4fV<>8gjK=1m>v_K7sLU-Y`w*`TjzRIT23w)uD
eLqxiO+l|#??+#s4Qjpt%A~%GdDJY-n!x=#&>tjwG*oj&p#@lDpM^6xay2OU<QK0hWkr(m)hchS%
#DKavrn=O$~1*#(ybNNd@{OG2EB%{^gb&BH38R8>Y#LRHwpXOZo{0OLYQGnaSRq3&u<XgO!G&7^_
*Zh=HL}1yn~J*?+c_MLr6R=(QrnTO{_n!;qKJ`n+D1RZiVvgM0I&!m3|H`9)+axUTf%R??*0G3Mj
WMZ>q9YmRHEOePLh)*A9fcMKSew@(7&;%(qJ@MthQTL+cqY7c_9vNISzorq#+IyMMM-}v(7^S!Sg
_dA^qd&d-|FXAhsC)A`mS6AaUR%$~n+6d^jO<@)!^TZ@B>KQf3EzV;$!>a&HPe=5$82*P9Q+N$);
cLxonOQ1mShPLLSZQrrTP2ltwv@NQXzK-0SCjS~a)lzl>pl`kp(vole=&pzgD+~is=D|p8S>;pYR
ToP{|RSeepj@yprS@ZSY{xKC<iL0*VcVCW)vc8!(urK7hjw|c{;e*d4yh6|Nb9e(j|QxImD~WFO)
4D0|vH_5w_B426@b4mw`@Z6!>1<&%>iC8khnOygwftAx1fcbVeQQbut884JqcML<OjyZi{91g>vU
+eelFM3^?9-b^dAbf&=}T%BnX~v}K+=#Cc8FXhok=Xeh(a+YZM`#sw{<hA|>feo=@`_IruU&ZbV<
Ym4KD!c6B&b)*5anT+FQk<<d=s$dyBBRJH^-ixAoG(;a%&_nLd!<lQHm_F7_{FBPK|2fJ!U$t|Pb
pt6BTf|Gz+)0V)NlKUGZ#qb!IwmiZgRN$CriyXn6gb}3!n$Eu=Za-6hv%U*?1{SMu{U$Nsxm2{4|
!*n-zK)D8KF3tnYC=FaIeY)&2AA2E@rB?wJAWXez7Z=%ytGQ8bWIGQe}f51%f)PJbS}6>?o_0<4o
<zc{=9Apz#XjCPaBOl}6sM&XH>IXGW|!1$uygDtbXD_>Q<z#t<vGP=1BZ*KwxiE72*gG<j(8PK<R
J8i{^jhtN^iOP+n!$Pd=NR?fX{3l}>)p&iHk7DF)9BKoaqK`I#H0)_4vUcrndK)>&vPQ{KuGs;=K
SZR-Soo%)XO<{RraA20>;G8~rBWbfA5WV)N>`>Mx6txB0s%CpmIZ?tH@`UFYV~aCT(fuj+4LfEZV
}WwH_<n7<OPf9A*oRecQ+|8tgxoZIkXabSxSABL(tM>dx57Ie5Dg%0l`)edlV^vF%q(NXF&mIk>$
>o2UU=K>aY_uyq<kMzbIaSPd8L-O<}y+G5)8Jg0#J6H;p&{W(tc%!yKTadO}yTA8APHr&G@0zG$k
FwohEhe3+?W0@v>#w?2w@><@;*|E0AD8<V_L^^M(2gR7!Sr*dn?-qRTPl%`?n`*y|j2EcBwyK~Y}
mlk{c8b;V#H5~hhWPqPw+HhwMUzY&^HQugI{Sxd(Paa2)vi<t8m(JnJH*}Vs{p$Mw5GZgekLP-gO
^xc2|7>sXX(uiq)RUHbo9mIv9P(wOPvDPHM7CDs5MVv7v(Mw1g6H(LX3ZgB5V<peV5@w4A0F72bt
P)?gC5I2lGNS7g%fJYKWdzW&qh(P+BV-meV4t*9MCXj(V9`lI8)_*DJlEr}0Ou<70%w@6e3sQ)#F
3_VS8((t3v%S=A`&F01Bl;~X>@Lq`$>8YhqTsDNNt)d*Yh1X%}K5~aRuR5liRz#65tC1#DkxL58u
3dWTR;-_+>f4ER3U-*l3c9spfL^7x}4&`ue^VxXRYgbXVs?I4u%mC);p&M?tHEdl|@fW2N?dx-9g
0-cn)+478w~PC9Kwe3N^j-Ah4u#NA_1T{2OKX^GYg<dCeUWVHuaqdF657QfX)@F<*AC49@Eqtwyn
Xb4s3-9Pp4DGy*@lqRtl;Jk^)EYUq?q=Gdr5{nXY)cTHZSFa_mmeio?0Gi_NbmawSyTC{CGv%FAd
1m-)=?M*uN&u@61GCg~)nctywc9L0APY+V+rM(QEkPsl4OPjE)wAB^Z+zydXtvzI<u=6UfkaGvtS
GvX0LDx#F%UBCq+L)+&K?9aIIL5Ulvff5joM4eObd5$CpfJqgRlZ;;RR$%wT9`_B;2D4P>Ip?I6E
qCEmRY#Bp2N-GS)5qwZ~u4siZO$osiCQD3OSVVxCA>kiNLd=w3jV!yuGD-l$IHS;_veQg6@&rq!%
Kz>9$of_EIEQW+mF5+g3<*LLtpia2S=T^wq18+~l^aNU!XhVS<R4(*-ZGTee&!5JFU%4aG!{dC{?
?h`+X)(puu23FwmZPX61Bf=zxMpXS4P{BwC>^I^Aa#lYBy@fl)RLy&PRT2ti@x+lO<Q`eBJzo6yK
{Yl{??IUFtX(k8LpH6MZVZ=>a|xqgf{saAQfObgmFGMbg=#XhIVIV}ebu0LxJog<G3O>E_ve-h>l
eh+JM=+oR~d|Tw?LA{A2t8wAuR*P%A}?3YBiDKPkUCj@jKrF{}tE#)KhiK-=KN%Zw~I1>{-3L;Xk
k$&^=Erhk4UIBK3@B*uQoi4C&x$`Pu_C_+?q>vPSB!&RPiAtEDo0tM@8fhk9Tx;l+ht=3BG0s+mp
8TP?AwVIdU0@{?B&;TG!`S!?+^WLqT)XO0eZHbD}y;pYOh$cx9UmDIMOBzME*X)k%rhTLet8D9N_
YLEH0D6u=T8!24AxJg&qSsk>#1}kz86(3N8gGb7dDhV;m`FLg?t*uayp0P27nVa&nIV+n@G7SgUp
OI$lX5{jHXC_B!)}+!2)+~3^7zB@e0Sdlg;6!AxiXlz&L;-^%IDLk2s$w($De`HZzg`dOP5kH<((
U>VD7k_TC9U;t+bryVUe<M)a4qtZr$80Cfz1psEWRC=jJ$gI>AIj~H*n6DYzrQm`eXdrWpfjKTjS
i=8u84yBQyM)ZkH}P=r!dzk#YWsv6tHIAe~`gTJd&Yq@|UD5)=FhPtQ??IBYBIs3ga@kQjaC3Xea
f!-C~p#IRjZet1BJbjpDf1N5RH4AAz9zX?8kbHdg!F?C2LU+=zowi{39H*xUc?B&ajooEwn_gH7J
xE{sW@dUrzP=In<Tt8}$fT~e4I2efBFs9RzoLUx`Yp|s2+L^6g7be4XB*H7x2_7iaWAJ6LZw7L^t
2Em7P^3l0xSEl7u%q2$n#Vb|@TK%I2=SXZtns5u)4H0hY=H&7W~Rw!VJ(L-Qbp~!rTH;TR0y@<x6
MhZf4hONI<8-5ycqBG!>V#berqq~UzOK`?C;pgzsV5N?sr#ag$9n_z94muJBYJq_z&M$Yu*ZuTES
r}=<<&%)R+ywIQdY`MDu=Rxs2REEBI<%ZLzx?@pf*^B-yCP66F=Aj}-lijoZZ?6D(;=Cp8==)9LX
(%<ej#A0PNUr#S;#j2wPCCtEJutnqk}7ZTNMj@A&>k*SgePGI7;qE2F=A(>6HaF6juh7!@`K~F_S
y~9$W`JQsRaecDsfAmOwSMZu}cs?ogCCv?qrFtT04>MK9|G3C#_JG}0<>{+i7<lU2xUhCFV_-klz
Y_R$g=wq5#8|Dom1WDi-nD88*p_NJOE6lTo~so;l@d5nG`8bllHS4z6;@5)#0<o`??NFMvj!FpMd
k&MjgqUXBohdKF%ns|KcNhegf;ott3IN0N&ny=a@-?V75!QPqCv;I1nOEKXL0fjS1=j|-!4ojs_3
C%W(I5FxaH9Bq39)fap9<WMFl$?3NKCt)KKJ-dc$f3S+$`oi>L<bLBo_@OEeNWX1OG<CEh!%w`K!
jBj+S}INha%b3~{+d1&d}&{15{-5L;dJ{7L<z@vjKtqM!xKytaEmzORXP%~j5h)I(Qi_;W6!AcgZ
LW&GT0U$4tDoJK@4qA*l5n`Hc&9u(cOjfjQor)DLskDWa&giCeIct(POPC~#ecdvxwjT$fo1~Uab
!(x6oCal@n2<^bD-y^kuG&@$tQ!!pE%j8nDogHG!&#T5`E_os4Flhd`lD=S-7Kg<nXk<e4U}5~2&
o*tMxNAB{E=j)GS`kDxC6uYZ=;T3jjjou9$Q7{Y)q4*fjT($Zn^ECqp-!=HtSPW^Vl9vDE$~$dPr
wnHFcGdcU@q0Ol`-LHBT%?WgXW*ons(a_mtOOQJwb<3a7>a8>`v2a^`CKl1*2HVs20d15S!!tnX9
;i39^>^GI?CTdUNea<TK^VYmOI`k%KpCwsjfMHTrPHqtNm1SzIyj*hf%(`o4){KNhPpAUlixI*1D
ooV>DCx82T7=KQ#@AXXEHaWj5GG1QC+e#|mn<CL(pX3&jjGle-4t|&Uyv_c!6lUI{)wQ?>*jZG)J
MRt#`<E?AlZ&5q&RpXK6*9dos~8Z%e?I}<``d5f2YwL~&ir;?Gv4aQVb1rk#C`whk21_MtX(5$LR
1HNdUdre%%3T7ll^tufHx^frzmoQNP)3M3r^t;!^kk#7z&asM3VJvQ>4vm{9*q9<dXeXa8AQOdmc
-7dxnztKk=1S=P}peG24}-&UZ<6?NkC82w3&=Ba(*jr>giMcm{KMn=IbPn9ISc_7zv_Ib-8$&jly
bJR6WZpjq{>&sF>0s&8-dlJ3IO@c;p5)_lCj6YP3xzDL-;A@@iQIX>lh5Tj(8-&xH(<^k;co1wYl
tluJ=X;nO02jF)gS0Jo#7*?&XxE2}q;ubS1%BY_KW<JMj$il36w7(9<Z>Mn<FP`VwReHT#P(qvm%
bbQ_9`5ZOt%Ek@hLjl(f@KyLMLtd`)Etp-%fgOuk^Obi_+W2<dw72k?Ej|NxruVM?xTQ({<=76L2
;yb!s%lSq$^mJAvuj<;&D~ie(%$!sB1xQXd_Z>put%yAXo9i@5~~3en}vg*pW8L`j!uNY>71G>Ok
j&?(CjU9kN3@bi&<5^?NK#>WePi`?WCBMjpQrk|z~<j|9wpIQFa5!E1SlswHO@G*}bXyVRt5QZrC
iP~YV-xtH0ywGO`hmbx&Yj_nI5aJ^+{a#un3qrB#8MrGd361~*1?h5TAz+flSwT~IHsAM))B>?30
N(<(k)U{<Dbxi)#;Az7e9z`~9qELF^uwB=PEkLJy!GKh3sUB{QBj?_cSR@tvXaBNcEj0wAnzHQd>
`R3`yWYA-H3d~2=Udi(jr5txU}|W%TWgpr=><g{M8#VC8H%qzOM}f09NO|4Q~1V<>su>Pm_!*l)>
-K~Cz8+fExj>VWDW{Em*nayr>~jAmt&fcPYBDADmN-wdZihKK=n%^ARLe>J!{`k-JtC_4ZK&)bT*
`eSBYftCS!4pVe|ionYNyMoHnMV&uOahbYQyRND^7?ABwlsOWcf{x^cs}(0O6)pmg7+?~OlW=K7u
}2`4vSl-%HuC$wFko0}i~Lf+3~!3R>83`@KN+R;rKsXKMfPRi7|v2_yvjOJN@F~^R!f51rr{w<DC
hfV1|*T%z^L0S1gtu&ybdf=O$)JY4vX~>i>l+KIQJULD&J&ZEx)&TKj5#7|TN-w$@+V#w%o7%=iH
CupL4W2WWl1ApUK%+9CnPW{C$+*lZm(aqKvsAZ<TZI!vVAJ#m8!w2I>3bElR6mxq<{Hx}E0sLr`$
i)-qnl}6k_i}L`y@9gh%QC}Gp-+jBQcW~IqVC@-W1nJwUtqtVsHM73pxOhBz8I-*>x9iz^RMDxG-
C)%IqjtJh_e>e=MdL;1kGmJQu5TbW*~8{<X|Yc0P~I#^9ifSNxLfZP0rCHlda61TQcr8zzg3DMAE
UAo5(XMc_xM*jhLkS=KNZnWGU=>76)>J$)m;aw~ydE$Wy*6C2*|bNVKUzbt>hxY+r^<p4h>E2D)h
U(CiJ>$=I@1SznvI0@rSeExHkPi-;@p=jiL&0z7QT%)~$*Zr_NzRUBE2v_m|GR{)ycwi|AO~|RXT
~=Az41$M+D7!*V_O5h!p43^2`3G?d4{pq5sN5PY^<K3ftQ=u#D4vj&T%uu&H6I!E;<W_4kaW8rjI
avY5T}+4o?{p_wuxRGkLsD;8_V07>y@X73hp3@>&gGU-o_T|^jW#g);o$foAs%vr$#`9j14Co_fQ
Z1H~T(0Aq_0wKSs4Iiaf1t3{0?oiV_f`XsFnTRBnMY3G9cMgezPmRg@1Tx`W0ROy61>%K4zzzZ^8
ft=f!%(mXpEKa3l*{W@W=Mxq|RB$p?Z?16XKLx2ixb(C&o(>dyU^>m&3o^;jBwo|y5b(<Gw1oYye
3Lv8{;TrOWL{Y=^B<m3RT^$=~jp<y#Pe#h$2Z50d=o;4$4>7s}*IuC&pFU9Ldd0;BU1W)at{hwR1
{+7g72n8b?OY6ajrMPtR*rp?DUHZ5|9Fg6PI~0xjBaL`i_<B3AR3Qgn-7Ju>i|c1cA!t6eL&JvVw
9a1aM%OIC1PYf=Pc!F5;%d;FGCe)l=3aoTjdtX1_s*rz2Naw`hj)JUuklkj7>GV?~krxp^hTtZf>
U*4;s_0d#@M$MB)LZ0HHfW@v{O!6fMSM``{Sm7y(544{|hMwk|gt^LXMY$pAzGGfZz4Ko!45Ew?4
r6G@EBm@U#VGF9S@O5u;7*{>@XAm-i+wR#=j3J5uu2k0)oI-bU}(Il22egTDORE}&MX?p)sj{08I
kP&Kq3a#eAIkN74BSL1tLDbql_=#f4Nuts=*E(v%(_`bcr%@;HpmJ^zJ4E5<aP#?iI@vRJNU`<9R
m~AESmj0Y!pO-=WV#sICeuts>N&N@-1MQH0!hbg;_yz<wgdlMXG23LXF43#=Bi@M_^jz|3slaORQ
E1)orF%-Wax?OiG2n&XDhcs<rBb(r8uvO7*b>42W(btYmy?3P2ce@EPLp%OSp18lhmv#z;sh^={n
fl(Af2|o`}z?I!B%KvQV`M&<*U%#zmrrqBWJzweKb>d$sqbzXrzo_knK>bEP_wNxM#d+b+<cnb%W
}a{l0t-f5tr_E2EQUz#E4@vLzPR@K~R0LHs~%_G~Qq0d^%-?2U$NcWnXp*0<<;EUX`8<A1IN82}d
L%LmTOX8&i?~f+=AsLfI)#ei3+EsI>IxM6Pw`;C!6*r>M^T&;C+dK#M2x@@U=lcJ+VaB|^K->ETx
pWxAToJ3q1_Y=Z9=LH9ILmkp=PXe42@7FiOx%*&Tt&3eUkDjXlX6GF3|+#=%OlY-Wy-sB>^g-R9v
KwRzFH~ESEH^qGG6;-ezRr8iZI9D0Mqpx$$F{TXq}i7qx0Gk>v%=GhJRL=U(=vYdq}t37Ih}P8+0
kC`%9PPU?lOz;3-B$OX8Wd-f^3Io%1~+iF4>^E#W+T)_rt>kK@@K1jJ0VIC0JOkMLcjuwU7AjD61
?|FW8!`foM<q%Jh5NTr!$=2*qu<)lgR%EOy*E(=5ddc90ID)6hfc)-7ZE1bI<Gw~*#aB3usZ8K*D
z+>$rM{`xu|6J&n^QO+SiDfJO5y2kMl=X36eH&e;M`7bzzCKf7?C7ef7?4$_^e7htDTRp5n!v<5E
&v6r0>_|J!D3Nr)@G%svAd#dE|P@OZI8QRqtm+_b2Vc0ulG0U0(LqDU?v70hHl(y<&NK<5xBAzG%
=`Tt;qOXqaj$|^m?j<f1kj@o&A|@k#Vz9A8Wyb++KC<h+GWpCaSkYY|O4}N-vUrkIisa)kQEze^4
F!O5l=X8Pk!>TTo&H4g{kbiwxC;@xVfJZ-q)q#^Q#|>?_P-GzUtWG!?>)fJOZBoVQ9fUT=su21=&
^Dmto)%isA+>u4)AI_NFWTq<R;Mdx0lo({<2??(qU(RJj^<v2ktj@Qxv4<>vRrHns%i`mT^&XeBK
s8qwk4dwzDJ9Lx1=KZXku6?h0ByXADJUWEBcWNa)k}A;8CMb;xvR4g!p*IYs)|0lFI8YEk^ZveWb
N8-t7v?irQR7uxhaFQP$2gsfFT|MnPsL~>!B`D~K-*M)uA*9pM9Y-NCPyPgy&^OdxngI<gEt+7x&
!2#*{~L1p`&8T+O&e@e2B69jxTn|hCz-0Sbc~#HVd;0n-)U1QuVmi<&6T%vHH+33?|O!g58&LAn>
XS>^4-SwNVwRk{YwWVx_dMV{e1lCjq36Ya3Y>QyjEWr?t$;hR%z!6wHrXGQIMfZqq77zJHrFtL?Z
KpK8w3iw~4v{==f#W5Ya@4Oa%d2p=i_RRSt{nO8X+$ZmNj@&m=(7d44G+HeU+8h(n4X6845s)M!j
s?V*ZC)X_9`!5@(4Rc^Iewzsl^x%<twTLZc317nGe9lxFv<Xp@mY8UDmJjJx$EO}f?h)hMRu?u~g
}q&KpDPM!qt$g<CJEt-cNKIEY*ceX2J723^913juxr#Wnw0Pn%(R4>dIY4%B;#vTXmlmkEH<yvH_
0;8MuDmurDEQEODwlEN>MXdtL^irUDUAJpz*6T`P%}2y=7{n1)XWJDif1zA?qvu84J4YqW;c>-C9
qt)e%+h9-WGZ2FS#ZlO>4*<083^7Z{|XXkc>YB(>KPF*WX6D6wX}{uB6M<3e`*AKcE4enP7>{p?&
lS3;u_Q&NuCqoG@TWW__)Tc}*MCBe0Va7%RyU_g6u6grGY<bC2iV@Di3D4O~~SGuYn`1V)zgZ^Vi
N9om{-jT);OL6>blePGqg}r9}zSU@Fj!<%I(!-54aoV+-_;6EA0mi@wpQbtrSOXsb8*6bK8Xo40A
3q$h3b1NHy;s4;_LV*m3ileVrwyG!)fBsHtQ(9(`WpB)rV0b*ljnc)*tjVZ7N3ZqxIL529c;~Nvq
D*j2pM&(Fd9FFEBx!Y@H+D+7EWT?g`o;54p&-Q3U`d&h`~%y!90-&K{v@g<#?}a;1f6Qs8UPE>fq
uQGPDGy;%Sxow&U^QDI7AZebv3;(~FxVDGSFi`1g3&f3By!bKpy{&o(<0HG-Pv@L{(<(Nu=U-$XH
W$ePB?8p;9OmzV>gri4h3sE)`w)MI;CC@^%&`?BFEwIgWM2c?^gTI)!e2<(1EWj%|vMc9pKAPt(|
xzga_{QVlUdrc8(wEjXg42lo!pT(~@m?bMGtDp<?poy4Kx&?`)fXdu_8rH)#M9r09i}HZh#uwPYf
lKrO9d*D#|I6Q+g_0`91_9@?u4}AsGi4>Xdu+xLamkk0Woa{a`dVkYEEBGW!9ll6C(wE_JrTdMPD
e*GQEfP`A59sWRQw}J7h+?ca%oBE#zB3y(=V_gB&}V|_kiVOzv<+q)r`3M4Ai))gbB^cS7AJ>R42
a_dFF}Vp!AQQ8NmTt>r9rjd8m76NvRgmwyZp^a!uE)lGOvXM%8_~woePq_0nm6oce*b*mbPhtW-;
G9q3i;WJ&McB2*y>VVuuXjHn6^P-m&kyB|(8%T}};FGQMz6(@*?&nop6H{7b!l$xb2TJ}zfs#v3P
Z9k|RKGWbQu;o*{JJN=pK}aSK=>*SF`bZO$I6GWMh4hF=3Az8nxhhv_c7_vWmh9##(YGX#kpx~EG
e$a_v%yj=bBgX*H+*h1ddWFZ@Y*?QnD(o;f-IqN(;w05yw|Vz5?>#WH5Lq3W;W*wNj0D-Xv3%t@G
DJhBm7e~!l5M|XyT%(MNKBMDse%kdpIBTx|fZ%&TJ@OyG*UCgM~us0R&HjUUyBilz@?40WeN{wcn
~1+R#E|XG4=qBFd+$4AsRRNt>u2+XESF<(W|F&MgOb;1Dp!_D2<*TbW!I=m!S_!6e3<F$KNQ7U?w
yb}tPNv!djToY&KQ6i<sV5?me*>CJFxW_(Kv^uvuabUnbgEm-KW<xxYA&&3n>GVteRvx1p**?5Zp
N3zl$duhYdA@Lx?AtU~9h%VMRAnC7I6{uG&Lvp>wr2z80gR!vZD>w=`Ov(;Mx2~e)rg_#1=A=2~y
ou9vG{eL_AHOI9s5<G4k(!ff!)V2+$$8<h4Cj_c$e+-|6VzB^YEO!Ipkt{A9eJIlGYYLCi=rY68$
owcXzwWaNBS(FaKo6$OqtJTL9fqI<k{kdBhkPHE|MfL<^!{h(2pzSTY-xVaI3tzT25)6B5DD&Crk
1|t!Dh_KFQJ;=Zfd%^>PZcgyE6A25n>3H_W%NxQ(au49H~}OC(bautUSXBmYZ+%d@nU*lsXuC?gR
dL1sf@gf=308wt?u9a5wrI{?ldo!hY6P|hmSYd`>?;8}?gaoFpCg{hgCU1Ek0gcbEsjY5LsTx2ib
oxD07zCZi#Q^3N#{^P@=i|p0e>*1@D56{2FAR`yq>+fF;pMQJu?md1zIOGR!-<`cWdH2)syVKX-e
E1e$J?0nhPoKYe{lb3L-~Z|&gRdV>o_z<MoxD8#@Dn^f+`q`a{r=@k=<LU5XCJU+51N1b?)1aE(^
Gu<{-;;Z-h4+*bgLKCj8uT~uTIWh*Pi$K)FTX__W0zxvu|FXzObG@rj_~b&GUbJ`04HG@a**uQ0f
JHrc{rAIDPl*<ipvkfTaKGxwOdOsvdv;`uUqzFzEO1=^gFZw{PB`eK>pbdiegkH`H^u*X1xwdl-r
45dOyiIPm=do*%;Zui$$R<N5Tz!YB}@KYn<3GL&J5W@x7#{q*T)kAC*)=YW0=>E|*1P!J;bK>MnN
KfSK}-;@9Q^8cRvzc2qE$p44<zY*$bI9jID$#9+*Dej{o@;jlTeJVHz21oxACuBqgsX|=#c&--BP
j1n^2u~C1w4xVJYH?r4k*D%=()t-GzIWJAp58xt6!h(mJlDUfM(?o`!R0)?RC<APZ0-`nq4t6&Pq
>Pc^Oa;Sr8cne<Jrl3+>(B9a@p}TE{Z^9Gzd@0xe*FgQ8kLfEQx`ptRP#j-al(|WKD5<N4v7MbO*
>1pA=UVgc42vG%4Ze9C#k3Sy~Q<AqLT~6E(3p==7?SX7i=WW$(O#soE<?Phms=3XBTse_0GE1e@V
XhC@O7TMDK`V{szM=-!^NccLDbtMVC<yPJA@uIjm3Ce>VBH>h%anO<3xr#FH5Bp6jE#pqBNsXz`w
HcGwAgHOpKSDD`UZU+{m<DW;{od-H8^=nBwQs5pm(hv`Vrys9~C|D!Un%L7)Y>5eNilEPNX<TrRx
(bHXl9-|Rduw0o5InSxj-ue-(BL`*3EfBk4(KKetA~5EyALr1i-kN<WXH>HM6z8zr>co3S%JpzjP
Ds1H0OSIgEw?e8&A00z=J~u7$dWnd6Il=>H|4ziizjZW>ib%JaK{a^r--co41#i66H4Z?%AQ$h%h
%vpLy2WvOEzmYzg@GF&B4{Ztb{aanzjDyIX~E1XlO0ECfy3eJ9Ynt)c!6OsZJTWHdKTBQaSXv&$8
lz20>A=%|Kv)8PSJ+M6CqKgHr1e5$!ZPVVt&s<2(P;b>zCG0`8!=OqAbJbl_^$45Q*6=z-|gP@tg
F#;zb95L_?PnyNjZx4m14-OytsbS3Dv1_r7>w1Ppn;&2UQ|}R-NK5|&5PC>11>n(NG821E(@XDAX
t)h4*<eXvqUTKqrg08+FY7o8Pc1Bs@BF8sNf0awTrm&d^1KI)=R6I+X%kK<3JbG+A(aHS$dL%#?P
oKKAu~}zE_S&)WFp;a{Nk7kxbK)oDk@^{&e^;~dr+NsQq7Y%uo}pi??LzcA<E5@WGGizz*G?ilZ@
Bl=BhieDFp{*A(xD-0uVu`fK7=V!<_DYWG2<LjCV4VYFb8sXX-<}oSIGx3Z@l+4JO-VyjZ(G!z>~
~O`MK!U&?EvEF2@2bp%~MLdk47vv_=-0$T8U63FAG(1mI4k>8bxCrkK`Ndu*$&%R@uCh-*t0J+B*
QMey9TkkNi%u@pjP2|MNZR)!s8CKI)9Y&4T(nwWs<P^(r)nK<mQ>!zjdhvwH+j3P-tVH8{tYkY*^
bT|7pq-Y{iaQfI>u~Lkg#j>|BT@u!NBLB3XgU-eWQ&lSqL<8NxUbD7iQj+144eng-B$*N(+21rY{
YDh)~&!&Zv1})(G{*9|50SEb__xJ(2vd-BG|@g1XjC#Ow?uztv@xc{MH#Ct{<q1TCvh{Ic=H7uBE
I($Tj`Ok`hkgC?d#O`^p%xVC!jZH??XX#pW*BP!tEUeQ`x&jL9}vF(J}yBPr-(w%-gs-1LHIVebI
Y2hobewcZ-|H4whf#jy2Dumurbdww*NVd=L<ifg<HJY9{FAu%vDKE=n|ICd$_V-uGX)q|>F60|9t
ZC%>WQ}!2TzT$jf@FtgjuW^Tc9>tSDv(UtUxO}rUV0FMKF7ySlT8qJ2ZBt7W-9w}?EeSw7Wcuj}%
`kmHs3*r}75v)oZPJ@8L7JP(9SK(sI6rjckzZjdsC{$IY3aT6EK$Abm@x+9Eo{YCb{lDEAMhyi=+
5XuW$jDPa|sq*f1z1V3+S%kqLo1lt@l~<18bwwL%z!y(uGJ3c^S6kHVl%G1Wfhl2C0M|m;W^eOT{
H}F92#<%Mvpi;w=>~R@YmAd^3`!A;bAMWcVRg*!KbFCKk2<Gl?kfx!O3O446RdSP5le{mP^j)NV^
$yg-;a?NnDiyQqQ(@#+W!n%ezJ<X!clr?L8N5HUvX&5YY%JWa1Nf}m;)#!<Vsu{2aejIf~epL8z|
TmQZl+&Vk{UeSCk5pCM!NNtong}&P=-ge<3UfAIIJ)Q!$H6nhG^H#(Czw!Dv9nX^TCZ8BHpqs;?8
XJxN(|>IAw;Wc5X3!2kS-s+&iL2_lrIYpX7HTnURaS+9F|^b@B~Wxr*N*4QeZ?&HyOB>lD%elw4?
$ZKSq=oXANdbBRnLFWc@HY7Qd?!!soFuL-oQ|26l;R*PvF(X4htmi9<fF8dx~YcFzsepF?Wv_696
J-q@QY2wiJ(Qo^{)|PZW3YvFDUt`Jh;3l2{|6u9}#pd)1`gml~(tSoU-?$AdfCZg2-UxPJFPJ-V;
98(psfbf5aaYvn9uwU<WpqrU_ax6xKku<OU>8QO*}E9xP7HDW@9fJm+j&D0UUQ`5>}n2#S-ejGL#
8R$f72z;`&kQ`;)3&wq6BOkU+pAfO^nEd#Uub)Z$1k&DdW<I<T6&nu~xt=UkI94x3=YT;_enl%Rq
aFpPxn%<u467P1RxKd_mB~g+j8ib!ISx(Ohd480ZD5ISP0qT|S^yyEuktMa1_t&8T^I`+{hmiqB*
{llKoT;OA_kDhPcc*O<8e7%NiY+#AFHV?YfNuF^|s9`nk?n6xw3u*wUN|Yl3*CPP(vUo$>@{Ym%D
7VTXE8r)s?)}iFhb^iuD$~R;vPyw{CibmKMrp`CSIyEoT=oLvc=qibD@;K;)rOl2^mXXV+x1u~bd
#n;hX?iv^dezCDZTVv~pQq#BYxIH$|i5BxVcHG*0%_KQ7e>t^R~%@<R?)(;yD-hbJ$tY0(;Q_^P~
;w98C4V7&9##N>g87JvXnyi+g9%0AWP&j?E0W%-AtzGuSXxQi3ZT8yOiaS=qw_%x2a#hQaEqBdE+
cm+|cQI+S_td+fYTh*=aLxK()x|zj?z2p`5Qbr0i2Qq9ky~3?Mj3V8)_`Dj0n|aaz34B&;-k&u(X
^S-_^1Jk*T~_u#$0q+vm}_6p=Mpz3hIV<8{FB~F10kfDT*Z=dLJu3>L}X6Kiw2zNlf{8x&7MuD5h
%5FS=}XZH?lLlB)fBH@_VU32#cA;hd5Ohrg#LWm`1$3$8L`eH>B^3oUbP2MjMDu#GLCpfJc3^Uk~
Xr$?9Tj+nIyq4mK>YrvD8!+`hdQ#LJyDR$PC#Zgm~)6b!kn`q(Z!9e$nJH;^U+Y;bZO$=>%8xhs*
#K%&2D|l@YYepNIjVeOlso)A}y?(TDXLTu%ZrR~bshn(ed3D~UWU+uSWVE@(-tPI^*&iHzUORn%J
4YCrc8i8K#MAZeUbgc`oHVjGSXVM2oD5Olb?iNyyo`jd^VHxwn(p1J_N%fUGp34vX&>uK4XmJhfL
b*+u|9v!p=qAp&7-aOv#R{lwR@BNQ4%(9-Jk(cly*H)wi<j=9V#2c(;&Nf?y{bEHk&POL1fGumCa
FLtVP{Ww)x)P3r%QH&wgE%a(q*<bXE(04?Nx+8=!BtcI>M^*vQ({&L%pKeh*_K1CjgYEJ@I#i{jw
mZA4lG)bd(NR)f**dMq`@9c>A9Xi<CBG%>=2UQ^01W-Zavr{)ci513SG^8v{t(sy@qpfuNEHb5Hh
ZFBlAdac?OUspZq{e`3JZ#BC9n$h+D?9mmQLKjsoBzh6iR{D@H4JtpMb9{BVVR$I2S-vA&3q<XHl
W}#E`3nsTM^Y&f{+JA9HyrE@wu%(VbHeaYp(8qRL+xNMqTA8vb0%mtyl#_=u=H7t6H4;vwh$2342
7roS$$XR*jBsEy?*a*QyjO=?6daCY#p&v=YVyb+H~`&sVe<kQIA?e-kSZIM45`-kPVEZ_BX+p+s7
M}RIWnC9QPInsDS8ct(VP*r>_D2_InOchLW^4N>-TNfUhPt9-6=CX-oC?XTVG*^UG(g@zygCUHPU
N6pL|iY^mehO?obC%uj-J8={8{+Ao{SF+csw20q%u%Oav)>Is~~Y%aH}PZ++Lbv41Xed%AeV00_s
Z=gI3n{-Rq{1Lc(228exN4fzPTkr`CCK_Ga+HU{90NgsOUqi0ij{5qfH@oIWiGPh6;ZISU@m=e-h
mUVU>t%OGp{)u>YvXt_GSJ9&16P~9;g-XIUDpS*M*RPM${$mg^P~~=i6J-++UsG3cf45esaHqyIe
IHOqR>?=mNY1hXH%0t2y1&nHP=v}UAue(W_0a+Uv0Q-6QRyh)370+e20Yx_zj9%Kl$0Lt8HlR??L
ZiZF`2Ns;_Qs*jMxVZKYF!q77>J`G;vMxwYWrTnpP*v+B~E!ftRloWd7zr@ECtA6yj%dA^ztVEDU
G?b4qkG09NjenqyVp3OJ$@5%9U!Bzp*Wp9m;RCnE;sd^$3(s?w2`O3(eTpgi7neC+E@L89K3e!^%
obOMM*6dK3<NC8`y*4f$6?hPP6yWq*&0#P>bFj<E)P}c$f}~58$G2f3Z5id0W8K*k4fnPFFz7F(s
<hQ)(U@PJJw-$$J%f6(8#FJSgM?~IbQ(@OWiIpH|J*6kI_@`kFzE$4XfjZcumHx^*veqds_ffIb`
?ChW*i8Q=h=c%&V=CIxfs(7lu^xYK&s`cxAQ@ES*tdbNoF2PS7pspds`VEwdtLwu4#JFOuY;;RNo
1{v*q}BgRr*V<G^gzbUfIqRo7FY!4}J-d8u;}RFV#bGMDqsI*+~9TO8n~GAd(Bry|rbsj4{~ckg>
$_!n96R@m&$HBBrALFm{uk|#+N%;R)HxiZC>*tE1$2}Ku9Li*ZVvs?=436^=ud2E)mkSI9aL$;_>
3Mxm%BV|WNrh-shj0VFICAu<aOE;p-L5CFat;KyrW^ByLoGhxM{^)tzeLFUKyT@u69m^)vs%=NsS
-)~2y9rrND(?Cn8Ow*Z-G+|f??Gs*3@n47+6oxnK`QNS9LzDx0)-vB%k|30;1#4TXQl=~+ulv4ai
n2vYMMz(Nq#HQ;1=oikYk*hG2z~&*D57C@-$WI<08mavioo2X&yX34T_J+G%0gVM*i|`5HDsN2JY
Q5(@Bk=O%uwZ8UFn9NItgPXm@(OK+{+FGGCQ9ImO`9<AJ9bXYl8rqYej^!>~9Qq_2t=hXctm9+4U
iuzWx<g5oBfOL(>3SM3qz_Jp3(dAIlT&leed5LOKf>^)Wm2)BOznT_(>^JIas7HK}g+Z;1KlJRRX
UZnF<g7VBRGKyf0dBULu4K!?pbHC4G<fm7`DZgrS=({tR<JTB?aF#5tB@JatQIoHee3q1G3w(u^v
?&oPO3#j?rVRBNJ;n&ExJNKv_zh)p&lev#1{^0d#8`J70yjPlI#;86dW*37f=!}3zsw4XCd$!1Y2
98+Vnd3UNWl~1;9pCS^f8uR@G9j*kaNmH11OhpoIs2fj(HWUjEcMzumL5UHx$0bIIEm$zDOtsF^7
ER$bgiLi&i!Mm}J~6MGsf;VZSI~?I<rYM|{Q53X<C%5kJW!1RjxhU~ljaO$8NCRY>uR?E9ihprWy
H)Qp4eHuqQUh;|#%5QV#<#GvLkX>z4E0)yPNi#~6+fycPmfnS78Qs5F_;0i)x*U5ywW_cTyNqvOX
;g5Juzdm_&dTB=ROJ@|okizn+FCcE-=r0)3Kt6KDoa*bUFj^SRR~H$98>?f%B9K@A&k|E-WfT_jh
h$vlB#3elE8a#JQ*jA!TX0N9+K9^xBOHO`(dCbvkp$5?3BqotyVu=63T9*^k1?wsU=YqY=yi_v;O
SL*y(BApLX1Pz1mM7wqYmRY%HsxWg+4J|Sk-S&zI!wL{`J|1_rtfR?}o3?0}gN4y3kwjDA?;jk38
~!lB>>$s0N%3`GRq`g?m(yDWV6I5-0c`qflN+Do{+|N!IeX38B{)r!U{Udo_Ia=JhEB<x@vKQJP?
$OmEYI^GNZNVxDG6?Lp6ck|n4hsJ?Tqrk36EG#F3g+jKm&8k+{oIS?&CG5aZuKB+y#ZC7h|;ca)}
ZFk{ocj0e$ij?#E#vZ{qo?f{F%}dXiYIPU2x{Io=9Q%x-uYWvM$Cuik>{0Q!7hsU<k|}S$+dT@BN
ebxw1@7}?yySQ(lCA)o3lZ(!|Ks$#(+_W653ykh`@)RLB<cjG==8xs1X8X8RFbIDeJcP`_o)ShRP
Cqg*<Cb{)V&yX6k1$SU|QNP%mk7H$phGMm;fp-knxCv4{iE*cZ0u?uCS*co(R(%DD-_Nc!|5DNUM
y8oo?^w01y|3Km4yZXRkjPXdCtq4q8|Q{^8%p2M7ID(8dQxkIfhM-yZ!1AvbuS82+&P2ixgc?R?e
k;ormk$6qy9_chb6nrZ)$cJ{o}IyyM|%xQ_h8}`g%NBfUue7(c{?b<m|3uc06@9|dx=HA|x^E&jk
bI`+Bq%^O?gYDW8U(j&Rg7fbf(2=*H|F^p*ZEo90_OGDqauvCu5Z;oQ<yM?TZ`WH+^2*M>qZk$n5
+Rv3L@)$tiFWzFzdq-{LBe9*mvy;p5SZzi>FMd|>FMJMJ-V#KG$EKfbkUFym7>Rtq7hL}uXj0OK!
b~hQ`S?GmI0hoz02{X^r+kKH3Zc6d&H>i4;4^<)O3vv{2s~oepje^FzPo1q+~4>Pe9VhcIoUiER7
3&dODiU%V+{py6h^TUehiqarbmET%tF)><Lx&o8rlkH%(EmKk5pe6yuFKq|!H!qSqZTT40xO3BCa
!rSBdu)l>SU6yD>SCv<91jq>ieE1ao+K5hs~iM-E*bU7UJ@J2Gc{$<0->yLa$-OCGxbZ#IuB+dTV
gLDeYmB{;yms5s!Q2=$q_%3}=Ck$}VH8KuuO_$1920bN&hBP(k`H;?g=K|?mAYBX^Lh5^vhQkX%R
PRFj)R46dl+OEH^OWHY3!qLI-^d4b$^ezp2h{dxbWV)#axmaMsyAxdr}F}!OQxv7P(+SiQ{FPTC_
w5D7*bDI%dqJVGr062(S87s`eQ-U`JkzM+4Ujy`-JfG^YP_ZB7E2@;)x(#jJjVtb;G^~sZ0dD^M-
Q9P^ny`!KYKfa9D)&WHK0zilClM2g7jz)Cq)eUI29hC0vwn^<+}G^g*3K3nN46gpqM~*ej4iLrje
fp<gf{KFc|jFmAZTj0~Y)GNf*|KnUZ8cp53852?WDocCUb4u(x3DWMN}8TW>~V*0$jcL)83D`uo*
K4eMi1cWP<4@Uy&=@?fkAC3jo(^0NeKIC2Q6r3xSkN8;sbfk}!$VaTV81N?k^*A4!!)KorAcM;%q
I|4G&a8Gk7>=HZ@v%964tco<3;ue9kCn(-eKi`6nFDu)nT&c35Bp<t{1ke6I>MF6M@&wqVBDNPFQ
ijXN4XOD=u+0p({ZjuJ{BT>GSbhxMrBKRJ06oL#uUL6xj(*7roTT!U8`zuZ7zDg2l)X#n?<90MjG
9~E#9Haf;_|f!ffTHtGZ3IY!kFdE86z%*Tp{Mdc6<vG1Ttl;VOA>)1l%WkW((ZexG1sS}i3BP~@H
oN}*9v^0*E2n`D*1uQW|4<CLkHE>|B~0JWmd$7S*mrSU%5n9?y+{)k3cP{UTp*141jQKyWNmRk4#
c)a@Q)o<p)8F3=^ErhmNe@@pNjKk$BuqtBh4qchpT)IvU-3mQ7JpBQWf8g^&+t07-fOa#5;H3*Eh
6zy@A5nvZ&flK_T?Cl@)@HtK`!y+~3M#X)3up<Mp>E!dLZ$hQNsGS8B;g8a*O$2_D3zO7%s#o??k
PJQzSzdglrB4S7oNGH<WxF0@0b>2y=_F*`xY-th4cuwVWHmydg_efo1kTH-CC_b9$aj;+YK!7zn8
1J7T&edvg5;hyInw<$(o8k+V#^K!H)>qk6<<<>`a8ciT<FU&1QFb8+6f}jX_H09qL0V=?=b}Q5WW
+6rajl{y9HTVV7fC+SLjW;D_OK#wAxY$2%=F<uyPTa;5~$`G#{Ga4~wr#i&jC-3c;GDp=cQy%jQ6
!#oJnDffO}igBo2m=ts97EKs$;|)N|+0FE^rS&?&hh#rZ<NNCc8m9n>qFEBLfiuEDJM=6^r0JFc=
a)jeU*PYfL$fM0uMiq>uU~)o=hcsvf2G-7%ikI%n2eGy^=!7@<sCC;rZnH!hWMs#Jn`l(H!(%v2L
-p=!vcZFnLdQne`xpY4Aa_v6Z9r?#09^g0LfC4O)QmFO8Q1j{%ce5{{GAu6!29h_6Oeo0$uHpwSf
DJ5=KtA)Lmk)SnVIEaZO2{(e4tfyytfGC+<lGV!1L#V!_Xt=_F1w?h>$Fe%P(F-L@nRCRA7>KXE#
tm%O+U4PG`R%;GvF+|DXU`9YGr5_Sbi9l|W(g&z?o{6zTRM;=&_jWEt<2zJ(=%;#Ry6a>9soyhN}
LBEhXj{803rpP?QWY{dUB{MKD$N%*j=pAl=r>&*|`glqMGR=O?IRC)ueDg5hZkFp7EM~M)lSn0K#
#KaKn6J|%CPMAlbiSqDa$}ShkMiB+7Ti%XBXdz|7(3T)GFc^~-y%jdusZe6u6^Vsu(hLEkjbDYxn
^h3pSdQ`)iSmwr2&mdpfk)v`PjofI~U)^xEJq{m!U9_w{VN1*aT`JZFmrE#u17Yl+wNvJj5XWEy$
lJpW?#xrQerSAxKEBVZMomg|V@cLj!e|U~YCB+DTdXtgt7=1~K<DK5J6i<Z+o(7)L*Rx}Z_H8yV#
oF*sdbZ(=l>2+=}Q#(|RUlt`A6flKOglaqVmrsTjkD&!(flJOJL4Lz6)=UPNM5ib@@!j5#xCD`Db
;y$^cec8k-niG#ax}W08a^{Cj&m1@*d4VB1p>4O|QNYa)3r=&+3L#vmXjd*G(?_K&@sTx`J$p$rI
yDvOJch?mz2JaO-~9aYw|~94Dls1Eic`z$B2I&v^PHXh$CxJOI%Z>8$o77eAUls1%Z<Ox_}n0yI9
uwlQBL5bu7@|~SB2F!Eiaqy8RZn)9I`%BIV6L=XMX1FBP)`np;Z?6P_R?NyX?>ouj34eMiwo|8px
HC)lG&O)<Fi_ZEw#mkT=5`MnkXET_kq&Q?g0q_0Pr3*<!aUE>fG`-S(YRY#Sk9=4F`R37Gn+<>@8
%3?P2~;uw)%zb_VrSDwYcV3-YHxd=^lF5n3L*YA&u*O<<$eue=A><8;KzDb~kZ*g2uG*8xrH0*_$
MyTcNL4ZbG-z^?ohuUv@((wxn7>rV}of@`eeHVXB0yQ*tEmbv%J2uef9QTK2rCpGysh(viY(pBs$
UTC+MypHq9^1Bx>JyW{{g*6=0R@O?Ot*(;btGs4ISIB|gyKU)7ISc%S@Xet%{F~(dW@%cg{Dhi?4
IMtgrYw0O<d!c0f<Nr)Bdo@wq#&_AC~rY=xfA1Y2hx5gPZc2*{vh&HLR8YMI6CEAL7lzd8aD@BnR
XNGnc7WFxet{ihGr8FN{)IRUoFkV@=Hw;M|E?uKn}X+kb%c=28?78o1yK*u-DJWcjqCw2S85EB4d
al7+8#(m>9_%Y#T1X4g5f;Uw{h@%{1!0~yoNolMGCGB{e8#PIMpVAZEXE@TN28;kg5i~sA8G~sx8
5DTDBWkH9xAt{KR)K2`(3yxGczyb*(QsXpj#k6$;0sM6J_Ug5JjIG&QOFa=@W@br%;|eOc*)`P~a
uc)eymkOIMGj<3SB=^*)Cf}7qTC?A4_6$;n$B?Udm3fwqnTeUW9Qf72Cl@T5@z%+S>C<d7Nlp_uL
b=M_Gi1bnBDSbNLJ=*JNupW!ax!66BZ`ZbQ3H76+ya1j&$~kA)qO*TM<9z!Pz5!{RCgb;B97k7qT
)k9wzO&s8id)+24ZJCswbv$$%N8;F~zbkgl0ya?c*d+bmnC%8}IEp*w2v%yMW6B)-k^F@jTKit|+
WDSRbbQIlxno_UyC!HRJAxIfWm-@=ugJOagpFb4bM(fzUKWzH{j2^bzQ_tz<bF0E5#R1c!#0_t76
s_nI^wz<9xf+<6EVh77(nr#9u8g!fh)Hr)27W^fs@<nI|-%<lys1x*(GxdAFUoN6YiUx%pMqM8@?
l$}lcdqIi0`7-h3u<pc^$vjQ9RX!0qhk^AX}NBB^U~3}&SaQ5#f}I@yBLp*2HFM$5#~CgWW=8Ex4
r#VqvW>pqf=q3I3yYF){EGNr4U&tM}Mj<ub3BM@77&5<Xh6>34IX`ZcF=`L*ab2(`3#&(zEuTcZ4
}3&l3(pBF8q^n_wHb!+?Q#OOJ0w?^AMfF<vdiPEcptp^J?+t9Q62`yhBn7ln@c%P*EX2%J;XQMCG
JLb}?}!@KJ;Q%dr~?aWMtIpu!Wn~^BZ0G~iu>wOEjpt(Kq-uuTU1vx<(Fb)<=jNJ<_K;T383rBgp
%M($gT$}Cw>xTMgkHMtAV32mZqg9}j4yOxrmAXlIadZM_VpW|@{vcDn#bRx}EDerlng4;xQ7jaiH
#^u67p~AF1^<ey>#{5(Ro)l~v9LhR9F}gRkUjPAp-^j)ZClh2WJRXU0zOQgmRy(d@ctt0v~A;xFI
+ReRG<@y$M)NF2S?l_pY{u@M(`Ru&?3isy!b9&uJWztj+q4@)}*PZf8a=_auT{@8qwefq#)?;)`4
~#qobW{)aX>1CTHj^yHJSt8MGA_q?C@{-}1dBkZm3)2_SEy%rgtS;xWAqQwlocZZY=;dP^>rH|)Q
};8x<hxyc@KcA~rk5suG9IWAr9b}ma~vs+aN6%M1QVN22&<;j@_DRjG~h2$GL1h0wJtSEVp%X)cd
iMWWlXP=TJ?`a6BfiH^tV}ea_!?VgQE7O=AZ{lVYUeeVh!~foHd``NX8}f^Uqb?nrT0XOo-Lc6^m
h(zsU(_*oO6***8nR-mT{wh!SAOwwGogQBn{Ll0c16tH%kEcn3<nA&)<CY1*)3*&Ph!k-#5{75!P
1Vg?@BNE?*1N$9VoNsTz%_j6c2d>J#y4U7NKY$DQO5hJmz|*vDz<27fc9tI_icv;6^maf&4;cEH_
Sv$X?j>c|G^0RJg$BnFdKWJrCo>qBWD*=bJ49;9Kqx9(mtf{pahKKVCTjlw2Y+7u~v6YUOk;87+A
}oEpBgPT!H{R5Hq7_ghjt2M?&ccGeS|jI<AMR!4on)K%dY;K`}4)N>ZQNL*ok0m@wqz6Yk$euY$p
XKPx!?LSp$0<lRVeaME8Jd$GSJ*<qHZNb%7F^iK31EN5(KJ!R4_vk;2mpyxS70$9WOdfqHN|~OO4
33EwbKUmnIP=-mo3Pj*vrU4-F;F75rAsm4`Tf~<&!0aJ{&Ds4r>i#sJhE2iqTlWE6Mg=#t2b|7{r
Zdje(rqy<=3CC-twoiL6COE8aq^U$~`m~@+UOOJv$APzl6->RhpFIbjg0!t2Eef#4U$Apa3x~;}1
g_S=U@w=|Lz{T`L_UfQVm&<J-gkFol;*AZQ$p9$3_25iF}tpyoE%b37f>|9koWQ-OoyP_PjFznA|
%$^Q>V5ll1wjh%8>#aC}$y?pIY-8~L{8K;q<QVb#;>T8kSIaalK%jl;Ncl7&(W1UrJrR2~E#l7}u
q`>UBM_4Rx&yiQpY+F_@>Cex1s#^3%RErKE@!wwk=n(SPhzzs|7?gdcpG>+F{$`gs{VWO=o;>qKR
n`Ce`7K=+vhcM69wR)5PG+$9H@Kg24@KWiF$v67uUTqpsPT0h#R~aZN<_c~U~LQ@2d%ahakxlRk!
gOafTbh&K4_I>EoZ4puS|Kj<1#3Jmo8S7aV<Z2AuV|)ccr*ii)Z&ilsOI^%=ioaJ3nlz=aGf<OQc
^|X$~Cx?ljTv90I#ZXzXlSFq`zt_F_7of<)sCbH;}=9uUZc^J3;d+^4mC8;*qi8d&CzicWp{7C_E
=bNAXyfOUD}K+9lx)8jY2Hj3G{x&y0MA^Qn5I2sC+lAu@M8r@?Yec^HaD&|hK8mh7k88SZrM;79G
G*5f;RAlPK-LGr5yskOdFx%}Oso66%dq-+2wv4E%NRt=tM3J7qLggFoKJp!aD*rvIqb~&#*-_eQx
;CH?dEUYVaDM6HF6__5?js@>4-jVnH{82DuCNL!PCi+qce{Z;I1+kkzxWOI&R_oix<c|<XX*Zqui
Q)6k#D(oW1p?f8CbrD_!0#B1zmgjD8yvBSOu5c;P_oM8lGmG6`Pz&lBtdh<*b~`u)HXk>=$Kmoh^
M3(v1J@&gZ(F@%G*<V0h_Xs|1)w@&5~*4BGq_Jb}RxFOUYVe))-Kzg=fH@lddvi1VA}lHOrpIJ^l
K39!zVf?tFb#|xVM9m77cTtgi~HNL#{l-zu0O?R_$uiC*Ggv}nWYMb8B9{EEVaqD*PKLM037IOw9
6<+)?i70NCAh}?lBsY2i$JPq=*)F)j^basA9C3{7s6dp?(gj=OQ!e8K_@Ulf>YA^xWaD{go49J^q
`(2GxzHZg7#VnPVdmgFx8`W-5;n)f{zzgXj#QRqn1FeceMnYe@D|N7OlLKgooMYk4zZCEj-#{@OW
&=~8q5h)b)S*K51YWCk|ZC-w;&OtH9{_eAu5|mPJnrcRoS=M(e*-*Cpp?&i0Db3M?Gs&rS_xVPRn
L%{P{zYti{;FxABN6G$8O+y4!az`B^boWBEoK8<iB}2W-GSf(j4<KXG+&HI{UYJ+eH|IGLM$#l8N
+eMn>&=Me_yMw}GQKMYFM%wxHV)6@lasD}r8S?r^~;%RkPFK%ZQiQYp%`YWjud;repuc!Y;dJo?3
SmkZkN{7jCl{se(hajF}2;t(T!m<#pLaJ>Zn%X<a3uAu(M1%uoQ<tJqw~jy%#*+etO6EQ}YPn^qX
yTjjKiE#veMFaoQMSgaxF!6@5C0Rr{qf~%Os@30!oI(LZ)5Y|&uX#rMKD9Q-*$|5>Gkn3-lf~y;v
l5}>$#w#e}DZ$v+h-($8^n;%4)fL-4*|nNuSNjr4_uWag}~`3m|4ohi!J35R)h3cTd_9U{aNx+wA
1!K=;_y1aFqyY3sq)*8V%L2CK5}1ph{BW9F0X{7+mYB;Q16yen-<oMl}U$0gl^7Q$o|yx85ZZTw~
~(;=PUYCG+>56i$O?0qzc<cwkOBRlAC?D<tVeg_pIMbR2_;u#wA`r@O)XP*SD_Z97AblXuZ!KqE8
1pX+MKvgwT3znKu;N;fFI7Q?0p;%AhFYGA6(BktFAoYH22uO=Z$u5PnSP2}h-G;EJY#D@}9}r5N8
K{VTB@5MRwT9Id6Hr!Y8-1)QpKUv)^t=?c{y?iUcPL+cLj_<#5?&ZPfV2a|5sEQ$gpO9LyHcmoAS
p5kEqj9ScX1_RY-$+uA}GV*0g%}=RFiMEE*eIKPat_^MJ^2ZZK|U`c707*3|L7Xzqr;IY;tpSEmk
?4>%~&leNuT?zT<%B@m#w=%`Hu7RD3;S$~YHOmG@GWnBj1~$5u+={;IrO@SeXR7;9ZrMXEFh?3j8
QxnL+>wE4J!4sCT6^EF>bzU7KKz3X5)at}w?o0<3n&dc3W3hY$2hF_iA#RI#r)1TSr<5OP?<#dXu
1^qNa`O*ZsyN-OEX?=C)!0B+E9ZA+fX4Dcvts|~A@Q|aSi7QPPm$P&E>{wott0F^YIj!zy&$u+wp
Gob$FFl)yKlPkF1+0re0W1YhHgKDOMIU5=+FDWEglCS`p^kr2d)Z)?l4+6DbxgFb;i>oMg~Rf!u|
(Cadb?VVJkkpqN^nNeQxMgtAZvSGXpaY=xqkT0nAjWt;Gpc1u2{k~bH=uC`e&jVY6L)3SX0f@HK^
BAE}|WpHv6>Pt{ZM{l`s{p0J0WN*O;6<2ejovDZPCN%yzjgQf147Lj}Z1?I^VTT}+BkGdrpgE;?j
74M-i+#BTLrl|8IV2OQ{165j_mS(@!O7zg3D77hte_iGiOFts1*ExBrbWDF__I&<Et@&fDxpTD%_
l@%;$5Zwa}6qB)3=-n+dL=B*E`4;BDAqMi60pmD_>+QZI-zcXtVHj~bF^N6U_spi#$hXTh4Pa2@-
e$byc)51)V)o`;uu75zg`OeZ@HGRmE0e?7FHF!IPGu7MdIcDT=kQcysLrx*subLZU03!ZfOgsWvV
v=Rru(S2&s}{ZGwCAWYR0F&v7EI7?OIn8I_i>LqGSnxPdPC?m*-V6bArasJTF8Q<eRm9C7TvJ67f
_bjrJQKWmvuvRi(@|?B#73i0gc3PNKd}dc*uva6p`PT5^=Oy%TrPxo>w*Z!6}2>2gc7UzK)iU`!)
(IFJEnfblquQP7V$YF(E3Hp)KO01CVsFy#Zzu~{@A!0b=~&k2FletTkOy^tFs3|?)G_tkS)Kg$%e
jNGt$w-)9k4Y3KlAbzC?5B2}33A`ppXBg*FR~H_pIAE9;;;hhlC)Ew#yX?~R%%r^0@KlsNCsC*LE
ow@TcyDhf3M&pU3KdK%oA;s{@O74PA{O=gMc=TP*1!X&`k{n8fT?Vk0zvCd5506*g1dW?SGydez4
?x>$w#|YxAD;hCjR}#-zr!X*WFR0ka)z8!uw*+;dZE<Qlug3aLesu!4l_slf)kk!D5B-3fBxpC0B
pD8{_9$ckXqab{Y9F;~~%OdSdl+r3ZXHGL7G5(Vx1E?+RQ}hxonr$3bTv3A%Ww9JUPSn&?}7^K%`
MYY_g@Sq@l)yeG+VkMovbPM?+BQs&!iy{0WGfhi4o;cyh(o0Z1!?j^GnI%IJwD0F5dY6N~pzj%A|
5=aF*RIscP6xQ7+B57(PT{#Yj`wC~`f@NBT>Z$h729iL$OSe-Du2%4QTJQ}oaYMl}WgL^9{gseVx
8EVYa`ZfX5%xjW=#a;&ZdWd8G9l9RcNBIpMx3D^dHBX9B%0XX+;j64hutc#Y0Hb5y67N8%~wQJAV
5cLRcxjn;-2W0pX;J?T=tpH&Ri$mj(F|6u%Oh3_zu%YW$4DcL`NaSyLUZf_`i{is6D_pGj|tYZcD
SUhC&qC4g`0A0_h#HcAf6na#p&=am)-K+4Gt_oY~jQ`xr{>N!JIus+jmi6RAMQBsh`rr!K=Zp43w
LDY0gtuG0<jse)G>-PuYKN|iw8J8E;6JCyjVK(hp1zZcwxEF&$&z|b1lSHpD0|3kk;I19^_fS42s
-@R7jh($&wp=_2#X+&%wL{O^Y>rSUC+odC@4IDy&wMfTO)In5)F)1_mcH86A)UleAE1yQNLlY}9i
9edSw~-8qS2gqlO<%;qhE@xivv`YTyNSu~h0;XA;>+n@G{wn*>3|@1oyeUTTB}I>Oc0ET2T(Rbe^
YRB6<U{zj>+9fISrSNn;LI7h<)9ATxis3=nSsX4Q(+poUoF3sTqw^MurJy?j^F>q;ywci*Ts6s*K
*&`=m(W9Y1^wP*{gnc}T!umD3Cs){1|%T?0UJ4k`#sm9}ZQt|+CaZv>z2j1NPnA|Cn4!E0jWW$(C
3Q4xfnyNNwjjt>iRA*qd<%oEZFUH)<)I_g+QuYp}e)X&~QY_J|JR5=lGBGv`R?c-dYDwSN6{YxU`
O~lR%J&<DB=Qv@aHO=w&Ha0*jV$8<ddji@7Np@=Mv85JAwdm50JPl`fCyw+sHwcsaYI~nu)iUpQ5
^k$ge?v^$Te}%ZJxN-q2d=w3z~*kf3NCBN!|mgifPUr0yLXjdsm7m)sPFDuuxCbg!<ws#zlljl-5
}kIdv8eoG1w9N*2^1W#fxlrO{%h7PGcL)6)Q*iB}g!w>D5Ss&q>k*Hi7wBMeRkQR4JnF114&=k()
`PzK_?T-Mm#VoEHvbWa=$_;$;BLZ;i@LVSYl=2BiC~U9q4fO)$cuxvo&HROLmd7>LDiV+^aK9jx#
_DF+y1NL6i6JCqKVgix|~)WD5ZG<rjku3$=O$aRsbT@r9>urwgczkUFP<NE<K|LW65Mg5Ap6)_pP
j;A2*vN{-W8j)*G6tR9gBKy!NGA2dOO=ejpdX%Hk`yXBXIh!=uBP#{#OUfsnvqD$_X_n$Mn7-{9W
tES)-~yQKO+wTIQWga(*JfocVU+-@bQBu9^I*_o{MKsIG3fzayC0kk+3PsZMgPnO%lYmGj>Y-yE)
7-uh4oHH%-F_^LVrPeUrLewW(VlKPc%(BG8m&JfOd%$($HS0$bw)nW%-x?1LFuGJp
