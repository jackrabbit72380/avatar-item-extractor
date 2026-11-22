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
rem  It asks one thing: what to write. Everything is the default after 15
rem  seconds, so leaving it alone gives the full set.
rem     1 everything   2 Blender   3 3ds Max   4 Halo CE   5 NXE
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
rem Still one click: this picks "everything" by itself after 15 seconds, so a
rem double-click and a walk away gives the same result as before.
set "PROFILE=all"
echo.
echo   What should be written?   1 = everything, or pick what you need.
echo.
echo     1  Everything   models, textures, colours, Blender and Halo files
echo     2  Blender      .blend, plus .obj, textures and colours
echo     3  3ds Max      .fbx, plus .obj, textures and colours
echo     4  Halo CE      biped .fbx and .jms, plus .obj, textures and colours
echo     5  NXE          NXE .fbx/.glb/.blend, plus .obj, textures and colours
echo.
set "PICK=1"
for /f "tokens=1" %%k in ('choice /c 12345 /n /t 15 /d 1') do set "PICK=%%k"
if "%PICK%"=="2" set "PROFILE=blender"
if "%PICK%"=="3" set "PROFILE=max"
if "%PICK%"=="4" set "PROFILE=halo"
if "%PICK%"=="5" set "PROFILE=nxe"
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


# What each kind of user gets. "all" is the default: everything the tool makes.
# kinds is what the rigging pass writes per model; biped adds Halo's own rig,
# the .jms and the biped-fitted copies, which need the two rig files.
PROFILES = {
    "all":     {"kinds": ("fbx", "glb", "blend"), "biped": True},
    "blender": {"kinds": ("blend",),               "biped": False},
    "max":     {"kinds": ("fbx",),                 "biped": False},
    "halo":    {"kinds": ("fbx",),                 "biped": True},
    "nxe":     {"kinds": ("fbx", "glb", "blend"),  "biped": False},
}


def missing_rigged(out, biped, kinds=("fbx", "glb", "blend")):
    """What a pass that reports success should have left behind, and did not.

    Blender exits 0 when a pass quietly does nothing, so its exit status alone
    cannot be trusted. The files are the evidence.
    """
    stems = []
    if os.path.isdir(out):
        stems = sorted(os.path.splitext(name)[0] for name in os.listdir(out)
                       if name.lower().endswith(".obj"))
    absent = []
    if stems:
        for stem in stems:
            for kind in kinds:
                name = "%s - NXE.%s" % (stem, kind)
                if not os.path.exists(os.path.join(out, name)):
                    absent.append(name)
                if biped:
                    name = "%s - unrigged.%s" % (stem, kind)
                    if not os.path.exists(os.path.join(out, name)):
                        absent.append(name)
        return absent
    # Nothing to name them from: the NXE copy is written for every item, so at
    # least one has to be there.
    if not glob.glob(os.path.join(out, "* - NXE.fbx")):
        absent.append("no * - NXE.fbx")
    return absent


def rig(cache, bat_dir, out, inside=False, profile="all"):
    """One rigging pass over everything that was just extracted."""
    rig_dir = os.path.join(bat_dir, "rig")
    blends = [os.path.join(rig_dir, name) for name in RIGS]
    missing = [name for name, path in zip(RIGS, blends) if not os.path.exists(path)]
    plan = PROFILES.get(profile) or PROFILES["all"]
    kinds = plan["kinds"]
    # The biped needs Halo's two rig files, so a profile that wants it still
    # falls back to the NXE rig when they are not there.
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
    extra = []
    if plan["biped"] and missing:
        print("")
        print("   %s not found in %s" % (", ".join(missing), rig_dir))
        print("   Making the NXE rigs only - put Halo's two rig files there for")
        print("   the biped, arms and JMS as well.")
    elif biped:
        extra = ["--rig", blends[0], "--fp", blends[1]]
    # Straight into the item's folder, so everything it makes sits together.
    target = out
    print("")
    print("   Rigging every item...")
    # Blender exits 0 even when the script raises, unless it is told which code
    # to use. Without this flag the status below is always 0, so a crashed pass
    # is reported as a clean one and the player gets no .fbx and no reason.
    shape = ["--kinds", ",".join(kinds)]
    if not biped:
        shape.append("--no-biped")
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
    absent = missing_rigged(target, biped, kinds)
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
bI`+Bq%^O?gYDW8U(j&Rg7fbf(2=*H|F^qm?QPr0_OB2v0#F-?)!VkZS~P9FyIG{^Mbi6%DiE|qJ
Bn#h6{XlpkpF(?yyitxqOIO9TP!v*IXp9S=FFKh=lP5gT~uNk5ljO*Z%Bwj(PKi<2q~x6yBHCm!F
j_a>j_Eo1kUigi}3}IsN3%~1k`s&M5yf#1yFy~bdL?(5%K$em#KO%>Nf-=WX&I*fTWQbQs*=*jlD
5FA5CXvG$~TL=n9}-(;*3Q_hd5EqBpqcF;(`P;z^S?E>W*P>N1`L<Bd6_&^OJZ*BuaA)G1*Td;>s
2-#yx@r;JG`yhmT2FsMN_%Ddw(bEf{;xFIMZ@;(vL#c)j18}an|7Y!G$KXM^;FU|?lnTFJmH2Y%*
(kUnxBJUGkPMO}h2kM0RUAUl5nBbtRWgI-3E`+lTdO`>dX=>1OA)WQk7}6O-Iv+HI)OR2ahv$r_-
nopaA!`{3o%iX>Q>HicK%FqZkqhdS2@0hTu<z063>n|WU_fV7Z`5>5XC9ynqNu@;MUGxm-ZD7%Ao
T|XsmH8k*z|-MT)2?%JW!DOV@A{2ps9S>bs_cpi14$s@x>DnKJ58;LP+PM?o*d;*moe6iJ*7ZP|g
?%m9sSXd@2|YeMrwHgW<>r^=vvAjy+H(5W<-U>I6zSFX8Ihq;TPaI)N5On$i&?<L<EMkwQaEjWnU
36Ck?FS(Gqtc*Kk}p<fWBZr3A(aYH<fgwTiBV01=juSEyLrjUfthqR4*L)tNYI^Mg3e#0Fz5;7l>
By|G9h02E`hV*=l3zZMY4C?tP7b+jpDR&Cag~~^Ct$#k!$3o;I(pwDZ5Pv$($NKWwCk4ph;+ZHP3
y~A69S?@1XJUM;ub)HOF3f_Tj_|P%IjOHk!!dE-E;Ex+ui<5XtgoL;PtQlV5c!D6=@g9X`{y|i>i
H-aA|GAwetAC5g~-QD<j+R>Sy!uUv2Mp>8YfU97&G@L_v!TaZ$Q^7+FMhLp6nn$LS!>*bUUcg4ea
J^G!_&&*bDQOU9RdT%kxbTqE@u!*w@)V<Z8W-;AbSmDWX;SV3$J$8<5p5zxtR$VOnX$1yI<|q*{S
fQTn)zitBWhs=u-<#fnq<%WS#23l-FgZ$2&4hd4|2=|;Cs)W@H|2}^xpKFHSvw}?Qe44IZf_@VH4
`Sa`Fw80s0!u~CYwpo9UW)8yPaupaAu?z=ICZ?9IRYSKz&#iv_p?>}WzaLs|eO(K*T`2^NE>svM0
$qHJ9U?k^|3=Y80M&0z<=d9~C8ksXWi|`}JRx(?&D&Y1q`om~(Kk64TtV&nvXBC$Y>9>HlgsTMtH
Z&AZL-YJ*jd={w1tvN>0EyxT1>>+2&(rj7)zP-5Vw&xZUjBG=I}BIjnyp-|9G&m*=jZL#Q%X!bs^
Z=aNE)4z18xNrmLpHAFcXjjnyBq>OWSi8N*;=7)|^K{@HAGmp4Hd+}Q{uSKh%fl#1@a!x;`?9&z(
2KczqC2R_&pP?mPJQV4L<a9Z<X6V35KGfg=ipg~Tzz%}1cjRR_iPpBF8iGR0)9Eu9o_F3<R44*+A
gz1z<KQHAtlp##~8oIs<<4v+r&<YAOeGKKhc5s*Or&)4;wE*W7MWW!AglwRL7-&U~=LmNlYH)5V@
cUK#eROD5ndSvTBkuL<kN>*-$?&f%zYX1^VFJY{$*5<l^)7FTITNM1&Nj$5<={y+w}s9rqW-|-c6
+r!)X$mxh;aO>-%bb0+P(~WlR4mm9$<oGZb>ed!Ya9ZBNYENrFeh;MmrRcDHFz{p1)N?ZKJn<{TC
LDoKUOV)R<V!f9i`XEb<I~m+;9)>PP;BGf6`%e|)FrhV4TJ1mE0dS8Qe_mxUIaT&ZF)K;{y{h#2G
Y#~~>AkhVG?#i@-1HC?BO=~)F~KXA!c#5JR=jd(^Z(NDk-{X*=}PnxFBRA>ce0Cv`&%;!$mm=fLd
Rix+Bpzjruqj68ED|FV-^)|h}7>)CCHejcN-r){t5o<cYmnU{0t69?pzdofCp)B{)q`0FJ!go=z-
7MFkVj$od$JtRZQpH=Ms90x9D8AY@C4@@@=H9Rt9~RlWGw=?QHjo|l3L|SZp@))}v5ybQ<c@<g%m
$d3k|n?oNtf*7;<htI-*c(hD{ah|Sa&o=2~u+_VVn>56wQ2-z~R3K<_XeA5yF{>$q>XPTQfa8{bP
`0La0954jvLEZ!R!^sh9$%aK-Ic_(71OAVrKCJQ)-1mIog3Br;v^Hh6TCv|Hi83LQeRY4|NwaMQ<
Sfq5g{eC>=zVW;Q?q~-2xd9_KvOCti8P@V^f(o-Z@tUk`Q(sdE=iCqH(o`_Tp1c}~OKr{G5msFP~
JcwkmAo{h$VQN7h=9p;82JH$%PSXOJ^3ekv_La3h=<8;|i7@O8(5d>i8y*GR{B~k>XYCNgg~*cSC
cJ#u$`BuN7IWF-Ze(dH(0L4xk%ZkTI(_%ctKa_f-DQdE@KCI;oFT$8i2qRM<o~oUWFd3bu8ibhh!
weuc(L5L+l($MEH#j85P1O^0O%K_|Eh2k$L(e6OM_r!x&ywaKaS9Y@Ef;O_mLe*;@2t<TqrOo=3Q
oLhxc)=h=w<<5^jJcr>pB6O1dkdZ@0baoC9xGdl)>+GJBJl*-z04lJ-9})0dgu%HO1>p1c`5)%4b
K#>^>cK?^W-YuV#N7@30j<*Vhje)Z9BsvbEZ28?0yxTPkz)CGe>^k02EF3&^#u=*8NAk=xV&XVg?
_3$0cOEoRhwO9AuTWNq=E?1<`DEm94$+fZnmLrb8fDFYThMT1!*Vzxrr!)}HX4^GZs>VYHEll1Y9
$J-_C&J@*hNY0xYOH4N5bPDWc~ZFAHuUv1x?ud<JV+D@0MSt250nEy&<Ju8Z1ebo8di)hdg}hPCQ
ZSboCwL+8Po*=O}0KeS|^VwrkURBM9K*P;5&d?_J>WrMUVFTsC2HYvBor#5KdW`+?4jrZXLs@)n5
5uz>%8hL$X;|&txYk$pQGm%x0<;Ox8z_e^&AFLMY{3rNopEq#8N`oCZ<LwST#M|4${k*%U>SR$TC
fI>cY7#d2v!Xczp+R}>hsMVDgdY6F~wwg-}^T3zdk2#Z8BhUd#`$efJ20`y^D@#Ju0BEy5f6;@q3
q(+7ip|hAChV)Mxr3ovn1X%#SDhoPv3~@skqzvM3PBtd*#;iyXkeXy!nBdW^2;k?-_m^+%dvnd%S
{e!SGQCO+9CnZw*Vj}{NnOmk^V$jE5?PQ9T{Y@MQ=^i)7Ud4<d9<Rm*?3K~pW`e`FZKFD8?(L+H?
Sohkuc*A>GJl&){~y?KpF^i*mrho_VcB~5Z&6vS@(Mr_5mW|XK0MR@H#pDYlL(I9I5k}Ab{_%{UN
+8g3cqo{jA<b!Ta3sE?{Not&Hk?*59^*&fkLYGwE|%=rOIN;OiuV9J0CP<4+;Y+dN;0juZ9jkv(e
;1+!>LNqn2-W329o8LU&?tLQbWVRdDXd*WgC2S$Xuhw}*!`w(_=`lu)-QgbkWJlcQkX`9mn*#epe
%-wy8piBEy7}WzS)fDxvZC(0Wbm{axPl70em2d~!LtSqK&MJFY08nu|Bo_Q7s0w~)1>a!@)TkZw(
vAe$-!B*OBc`8%0fTZ8JGVQ2NrS6;2Y~xg*MQm^P`v}7dPhK+#b_Hud|s|YXI<Lzt+g0>O<^F6(J
mxF!-=*Of)I0U)@s5?=-uADtI?{P^^v8}pI9Ur?beIL<iTKBsDJ>jE$x^WQSZjyHW<tj(t^H-1~;
X1&7yF!B{f;|Hjk|J=Urhs80tb<Px#uV&L(vX+(L%JB9!Z!AMT2AH9Cw2*$F6#+h|E?k#2{+q@V}
q>LSoVVfxij2ZFP{v^2Z!oe*s)a(TC7bV^l)sGphsV2;J+#S{}~xx%L+to1%rTu_^9oagSfNkC3O
226s*5|Rb02TI@r_zO#0y(>~yq+IFa{%KSFv*(~|Z4gLv+~F>eMOU{Ah|RiAX>+s#YhguyjsYlBG
MkZkfVT!E&@BD{{VOzz^pl-B5Er)4!wvrmtm~pIBUPFxm{>@lCJu`xFknwT_~CuE$hRSm16Yyn)5
C}UCS>~@P46$<Ps?;J_<}v-N(HizaBaWIcIt|o7Sq1BYZ$M=18#CK945EPa#d`d_|H60VojE@`bS
;KL{5VEPc0h!2o$8oyS1R*BoNuh2Q@@-W@!h)a~A^fK39Duo|MuSgE1LO71<VnkO1&DEOoOmJ09x
k5T!u$?-q)EKzQb2c})RR1a8H_qMQ7ops3ATCBo62sDQ0Y!!CG>Y<8;(p~7MmHEfAH!@@k%AXCE*
r4he_2;?=gniW<HvRN;kEHO3FhW#l@@{WcOJNPQNKPK4t2cA)G8JR|(coVyX@e*yJ1pfzf@LBbBt
}zf(U3Kx=6uQiUPsb)ZneQv!xhQjPm)N;rH6q1U%e#a*HpXPRnc)AcW4bk)m>n^<t?RGx8m=f5Sp
&vi<~LAoK24yo67k4IuC{gpV;6cUcK7!{?20mbmaSc0gLp_Y=wW0iun0i|N=ZX?!b5R+oU3`Gb-{
>WYoK;c1?ohyD)3*RjHS-;64{HoF0ZH2lp1?{o@fwt)AJ}<EW#PDJ{iw6fbVEPaOHh>`5$jy{d8$
%Y_f?=Th?W-)XM49GG5YpSYNo(I=%;*6Uiu7r{5A2NH{?Gv9+Jn%}B<e?&_cqnA$2_4<6t8N+Tz+
3&j=E7l7QgAj31>_A8_+xLf1iZT+c2lM<UawFn;w=_4wpKB}Ejb1c~UDq?Y*(ts66CP*KM<{ko;!
Pv8>*yKFVqV&;~qJ-%g$>5l1F_&WxuQOltcM}pDc(qY*I0lNvwrt5hL%)CX{kPwK8~pR~)z6pj0`
-%$GUxqnmww^v|GIql{`IeK&HFR!<=bC>zI;!w${t8E6yse{F(~`epvfQ6#D;yGCcTM>$%{0}&C#
mg=~a4&SmKt&9YBDXmhlI<lT0kIt@J>YiLMo|5sHXkMB|&o|3?&F_PM}$SbAVqhs9{i7ylj@Ioyu
%-#!2P+2i0a6=;P2?)l%({O^NS1mlXoG)t~_@#VYMuim&zcMnrvCRwbh6tY%F@|dM}N{+3c68bTx
9{&BpatEt(i?V106Ky**;xRiK5i~1WbKuo8)0fdpy6f}3s21HB)uKa@_;0U&vIzMpA_E=*8f9PbP
a@q3y))Y!|MUe5N1pjAs_K9J@*d5FBz&zDk71sJH#4>QH*lWP2wC5aNf5NDS8p}(1$o**u>yXUAr
VjmwKoQjgRo^p9BR^3WSXBUV95-A2*Q%AWo=a+m2PhjoG0a;(*CDBujOYahbEomwiFkJw7L(h%(3
WTMsM){=ZBpG9kSqYvGl8Ungs{mTV1r;hrn)9oIAM|%qIP^gPP38lW44I&ggPR6H+qa+%Gi<=d`q
MsViZ>29~x_;jK@eDv-0@+%|hLur3`O;EK#odi12%0x{csZo%qR$bJk>T@4vZNzn7SM)w#;UpQR9
in$}LMxrbOhD<*cM`q%B)W7!nm(SGw)32+Kysp025Zmn@`Ld_K>>c@1u%$&+K^i}>7Yg<K6)N9o_
lax(qWpKL4&Qhrvco#pXg0u{e9p#H;M~^!DeSJq?h_yvE)X3BH`?1HuJ8)-7a!f<yWK#3SQ2{ay!
cI>op1l~rb6;r=h^<2OztJ@@VmmX*yn3~2j=$?JXC`H0?l473ZXhLd;;5TaNHIRp04?3MLw=v)v9
en>6D8nmNx~F{h}<clcx_rn$iDv=W{vE=y-3Ip}b_*DgmZh{Qp8nZ#K6FM_{nT3!s6^w?EVBx9a>
R9z4H^q_|!#@fl>I14}SVfOWnU^dQ2-VXE8TA<q=aH8>zp<MUHT$xSwEw9T?zwGAt%4tp@wHnq?m
`43C*)}7ve0w~!m`VNRHyyR0FqiY}|+4E0gi(Wv<yn=nc3$CHwgjy9!afW_WN|esC1%&`$@#IwTL
$O-Qp0Ds^qjhNML~a-rK^d^A(O&H_^eEq|l~eDjH%n8Ok~<!ZhbtjbYP39uiqD(;E?q^zdvMFpgO
%iYthH-f#D+>ZN(+Z9eYXN{Fe@|GeU1u0=mN4>qI{U#D2W)n5egOzLD`IQf?9_}lzp2Wniqm1Ex_
l3MNb?&=vmV$wI7alT6SBb*LP{UW@iuA$0Na9go?MKZQnNXlVY&O^9>I+Y{||K(1CpgWgrNCV(a2
+Jn0B~=y@QCIXC+XyZ*y{gk+c$F=PV=ocQh^8l~dqv0NotW&=Ak!h@sq$LQ{O+}+ii+uB8}_h69j
PHG3>s_X8j{|0&wKJG~6ZT3o=$Z(ZgcMXdmp5q8%<E6s05WGUFeIA<nJMaVTe*o^q5PF2JF23Km%
zzO_i=rBp+<gkra`RH*!Z+c6>Nv^vF&YQsd<~z%k?{8)|0jO`)2la7&FM`=KtcW4M()91#AD|xV+
K9H%^cCg`q&(Av+a#PNp3)TE;Z19y!o-&@G8)whvrCSwcNeV#Q$v4r*IAK1q?N|(ywj<B;@I^&2L
j=@<{ylO`9`Xin4Q?pS&H=j$KXgddr=*A6#wizvFH&D(iOeZ?rdNF4@li#7%<oO$^Sv+!rTymQ8V
7(mm)Qj9$Tu-Tm4mjHWhi)CsP((|+r)41B`bhiizz7{(sih5%<LuEL5ts1PZ9Z_J6~XiWQyt_ojV
5-{Ojc#@&D!*4;gRJaBFQECCIYM>TqHN#BJ;in`6=kp<ZPr+X>P=q1P=OsWAZrc!$G>_9=rtV@Ta
JY9H!os#?5ORM2D0Ob2EcTT=RIAk*MpukLNujOvv7&r7{pi;7Qkwh&z0T~Ze03cazHl&8x`6=z?I
_}i*qJ$oD67?NY0%)16l;W*BSGjrhY}GsC2zV9N^^JxNFN%a$=630PNO0S5re#A8;1H@e+~iQ^<V
O4fRFg+SKAwdTyBo;#i|H*F)UTtlgiU_0|%TC>)H*ftu&=sk$Fb9u?$m{cBx9tQ2yX!JH@kKmA4D
n`5S^U-bGcUifcfTu&0p=MDBsl$F&;JR(3I&`P%%h5Y&mSgXqY<9KmR2NO=@8=nYFKuwB_3ytS;0
2ToyYJhLyym%bLt=@d~5`gw%%wFz{4AGtV_?<JfAmctHqL|F%zQOJT?n?q~Vj{+P`Y-!rx&X)1n^
1Q}SMS@InTAgK2hcx1UliG8iM>gXC?m0yYm=FOEEM{ufaGQXIFlUAut}s!<H<s6-%zsjAY|vXt_l
W8`B3j$=)cNm)#qx}^M3q&&RV_yz83j%y=wP}QKs6}HT22(&;{j-P;J-B|3jaSiDYK<3ws6gwkuR
M5HxUgr06;3N`OMKZNYqrpq8+$4yR_V@n{Hv0FcrNhWG$?r5ji;lXv>9Adg~CF?Q-i=W$3`c1{|b
z6k72iLB*$D9nlE;0hv|@{EhBnx4K*953AAzM-3%S?t|+*%Xb?{yl_(s2L-76wTMqpOAz#y^l5Qq
4k8L#YaUib0k(rLUt9dh2$ndB?tu>c>Ms>~cf$-p1E@p3nK@7vgCf*mtl)65?sK(|a_tm?kz^BHN
d#igO#O~xyUemcO$x)?bd(%z*ESetuRjE<G+kh>8`KS75fHO8DS!S#XW60JDUqvJP_u9Xo_vOCZ4
2uYFMQYzW%mKJ%E6ZvT+?yg2eo}+>l=wl`+%z%pTx#enGo=6T}|++i++h*mO#BKkm=bxuZo!?Gz#
W<!KxtFt?h|yn(>IlQ;9S@Z(Ni?`$|-mO65?Lw`L%A@SVPix;p6%@lVD9a@uJrP}+=+!$Ie+-#tF
9SOcQVEz*8fov(p*jV#oKOmPM^AFDIWD>4VI%d*(U`JG9iK)V5IOu!oJO``;u9Vp<b0+IM{PxPvL
#VDfS^;Sn;eXI7*GJ~=v*A(6@jj1X`q7yH0Tq(c<{Xb{|uQ1SA&2uTc3ocWXq0Gst<_+GetwVN~U
6yrpjUCB{h2?ru2}<9BrUZ!h=4K+Wk^s_PsbwYiUI+ue%5$pxB5}VE8<yZ6c%a%sSOG|3D&J*_pv
BUI4{erUpPm@i&ev#Xy^|}9(GKelJ~Uv$|6aOB1&QKvI!X!>hxkEwU+gKr5B5_^ZG;03?J;_uI9H
oAxzhv-ACz~vlte0p`kT`jUeCI7XXtp!@QWEud2aR-sh=w&;Omj8<1YPp>N377aESw==Q17(okh&
(qN!4zG+1k-Z;8z>WJb0__$zBWKog9f#K1i&lmbPBR&1p#w)uLEM^dVmH0VXcQE;z!8o|5gQdSU<
MYX3Om=UQ_@iY93jyI=bRj>mE%PIw7-OeJCWhS+j6@a*}2qyMC(<)R?wU;&}2_(C0JB4g+Ud+>iE
WF4K8OvDWj7RoYL_*zp2ly%=^7KX2SF%PMBVOgWvPqK&5tqL$u>GWTntu4lOPi2zVS95Y%$EaptD
>e2FDB~3ix75Skx>Bw9raZ)rGb!pLR5Yso6ZW^CpzocLAq^@+P7h;R(HuQ)T_!NjCTovLV$P2Jfr
!)mW;4Jg>Pc+Ho(HPCSeVPDD)i&ZWRi6bimqWxf8=#(Troc89q|vHAXm7te5jL;$)Y040Kg9j*CW
8Q3K=TL^__j3{yu^^T*H0HKV?@hJi6v>QP%xwvvQWCD6Hn+BD=gRvPnY7QxGVFMP-_(ozl#`2xnO
nJ&kF$h#O;VYy-u6QA&Hvl?YA(lQB_&-A4c_JLqQsfw>#gR1Noub?Jz2xiqn9gDAns7PZ{X6~()!
>4gzH8)pVuSd~qGBrsvHYw@CO&iK~R#hU~L|6DL*ml#SC=9ldiX#N3s2E4sI?yX6ajWR{x!D)$SH
GrU@)7&1Kc=VKVyk9VGQC!xNZLACgJ#5@pt<H$tFYppWTSnGS+;x_ijmJ9de!LxELiTpkjF(y1>m
C&JR5}(veCo6Z=0@ybV;WCWdFSlOh<NhI9gn>-z9j?!i|Hx#;}B?$>{K)&LFU5D%x?qe9*cK-YlA
SB^O?KS3PYTTANH<d8*eN{9#wjDn)1o{IRP;182P%ZHqa7;nnqad@5>(pcd!pz1v5N?wqaA#!6k)
C+!hVqSdaq`{JS1Y6ep7hX(2aBbEbLTg<EAlHNPoK5jXe=abCoj)A;VIX`0o-ad`gNf?`BXfBHTC
XO0)leBlLGbQ(OYYB7f<u#J~BHvx10<7RW)&@$>@&$dVSf}1?0tncty2L}7S5{_WMpjJB`vCQxO#
*0?lkbytWR7If_7>h13mv$5Oq7^Xahx@%EScjlF>8?ayK;K2jZ_;3Sh&^|3X`hx>X_NkPa;OJ+A_
cjR#{FPMv$udz<#i*EQ*%s#VF|*t7!BZ^H-@Q#VOY%ytYZe{(_Qn^X{*ofOjcB;Jjabhp70z;@gT
$i}a17_U)3ASK&0qfSWibt#yoEpK+`mg}&7VYKiE<F&JX{A%LHXQoH8`Kg6=+1*v%jkQ6)asO8&s
usD4}4Ht^bUZ+Ss>hg>^&!t=5OYlhmpR@%U1?fQUV|W*~@bdEj0oxB&q3v~26s%PyH{@b>tuDL8%
`S^Xs8#zNFOG@H1O-um_`FnU{oPKX_db<s>%d_2-5(B0V1+m}*4+~rsC@qQ{{TUICq4
