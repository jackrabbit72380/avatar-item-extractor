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
c-ri}347Z{wjlaf(DHK!h)9~GWLaS>&&W#>-%f0Qw$q)oq+vrOBq1gNHUVmJI`_A~v(<_MNhj`pG
v6CWkw~ESI(6#o=hvO|I<3>?c%D^Py~W+mDB8LArw6NQ`QSV+9%RLJw79FU%3|-dINibjo@bMCnn
heKn#1Q=6_u+xDlejAdU#w_S^XxReCXBXB+84rj9x$euO2i|yuZq;2!86TESl$4l^2)MEH6Gp7v+
*3?mdsL^Xz6sUl!0tRMq7&tD-EOTtz9i48NoFwD>uC|Lxlc@7}+C8coWgPV*vLMmJYwl|?_`prZ3
x3Dx6#8to<6XBthepcIbt`@jFxos{zhG+brV(}Idt(N#H{;)v4dJg>Xhdp3<|VWL-MeTA>CvSkMS
t!C5cJc}+@)IfB)8ukbKQC`D5X0!5!CU{!Fq~>WI<@3cXn`cE0CC~3<k)q?(GL7QNGOe@f0k3A4D
^wk5smf*-Fpx#L#FafQZnGj!zo?=Q*|NxH4{p=BRH~9rbd%Rtv|=!^Xi6KjgoTf0A8%n#Y2_pMCp
#IrTOM_3s?p=X?mdB*yy!oqv+QX(#nR>ZFVP&n_TU3H{j4l5^5q<6mtMjGS2Yc#y2=*|c!q6{tbx
Jo@HK6my-^F83cgGW*bv>@U7pRRRWumvJ&LZgWt~p|79K>y;lX}XFY~mxoWX<mn{2LX42F9{EV2J
^KcShwDXYBB%c6pPn`Z>7uryC!zIq;2Fu1G}6(s`|z#8<9+kBB<u9n%z%zB=s6+Ed<i$U+vS5Z1E
q10^@uNJWUgWkh|Ji6;d{T_^!zkQ_XMCa)TY!txbGQWo5mPH28Q`7+Z^YhaJKmfoBRwXSE^q{+5^
d6Ro*JY9}mpN2gWXmqDKz0i+GH5l2q2g*_4>wtUd4+&em8S(RuU@MZ;B`?}40^OLAF^3imqirQ7H
}sIlL!EHx=e4PI-h5~2%%tpKBLocTIh9=Q;*}#09doA$THX--R3TQ%!>kw0#IJ%aAe`&;qqE%;Iz
QnU(=CKWo(2-qPm=>uz=YuLH)(DoI8g_mNLVYs%dNgw#@4~E28UkwlZ^--NxbyMD${n#q17GGn}&
-SD2+WuGDEE=N+s4_*Z^+mBJysn3ZrQasA;r6u--sFnFj2AfD2y@FEmhj_cA>h!O_~)5fW!%S!@p
{ot3XG;hmFf2``|YEql8ca_x&oM!y??&Y_yj^F?I_Qm+!%fG*fj-vkUV84G_JpKOlv%ieLdvW~y#
as1iFoZ<{NPqn|Q~0po?_)b${?+jhFW$lPUl~R8N73od%K{cOpPue?_~8H_9>XwFTv`2ih>zcAw>
2CL{csN-(z(`;_VLlXt8|gQ2C!V_fCKcqhxAUsM?XEF4iWGCkk#oFK;Xv$s#ef@W`^|$OFdh`1u=
hC&dTNc6b^=dd)R2>uTBfU;ToJ4lNsPQJm-jevuXU|c9Jb{n#o9zCcNjO_W<|(v4424;2vk`-1Pl
4uiw!l>5!r4`*%;ffK>sRVjXymD7}P5fOA|Ep5$9pPNdu%fMYM<A_P>^GeC%q!t-c6&WpSrk7K-B
IuS03nk4?ir#*ZK(13ruH|50z-U9$Z-is>#n2lkO6}$t)6jQs=m(ii!_v9*@e2|Wd)tt)Po#z)$F
T1)>^u+7Ms)YZRX^uC(-oMiwTrXUx<*GoWc7GbhyYLIH{rl78bSJtW#a35lI32H}B(W!eJFtHI)`
$=GH;xk9gL`|b5I@{!Sow4(@s^iYPWNfv!fmvg`5SVTUwDu7zFCttZ)X{mSIwIjfV}~2((5OH72N
4SQGlf}LLyX_9`56g+ofv6)ki?*74c!zwJUX~;lwRIPpc15JRU@kA5+}~Dh=E+gy_{=5YSGf^CwT
Dy)*o6_2O*-FW0}I2kPn1+*pFW(XzS4c_nv`Xe90{T9j_+je=hPodepT)m~<RL<<?C4|e0#Ar)8P
=ffRr(BVdSTOCF|$Q?EzPR2pwC5SJQ=4b{7G!lClje3KFK*hb`=8Aj6X2m>E@mfKFspYkK4dBDT1
aEPnu3^vR!61o%Z2>Z=+1J5->tefo7KyhFNI953;sU`pNxYr8M#!N8MRUZB(Oj%qG9ndvE23LqgC
AeOwWgk`XD{iQy-Z1R(m%8NNvGFoG08&nwee5V4$V$$v;49c*X6hXx`0k$WBl%I61!;sQ34D2-;a
W0=qI1;9<DMV3}=ApmzBAQ|C&vJ*L<g6x%V-XiQRv$(xQg9Q!Ea|&UsoP(Ft5`2bja#^s+3{8Eiw
g=n%=C-U0=TR}vh&`l{M|Ei-x0STO2$yaa-Cg%>TC>S-YHw+DwczTLLq-L?fkZc`8@0~|7p*6&~8
v4i$1cb{J6<F-|RCaqH*RAWWIjE22_u>4(1`4}nypSjoTBe4@7z_%~I1m^EyxZ96y&Ft9~gY-rdB
JL4?D4a_~%fJlFs;J=nWz&)7gZKi5ll4#N48aoqd?0~=-P}KsCGPin!~aEK+8y+wchFE54sphu-#
_6-%z%f9G9az)NGcM=nmwMR^UQ7!nQUT|@wy?zm{xc5c?SF#N`zn>DN$s*-G1-UV32$rm5Z$CiWp
>;pMO!=%}vWm_28S=Z+|#`|E@Qm!lLgXuMTuD(ZG1gt!B(1A_1m{bq*^tRWb#uITS?Tq@XgKUZAA
ay1}w9mgRIc;g;vXi>8x$h9VSI-2>{_hxtU)vi3os+r|R0yY;Qyg<835wDNI%D<4Cxd~CD=n`NL}
@WHNo1ip;!-0~lt@*myuAEEq5=W@IQtUmB=LT+XkDL(ro+3mP}-a38Wx_#b4)mx{}m^w|OKS2*4>
0@93w>SVedv3?KjoUV+!W~{K{_`=hImo{vG1+o=JjFYLN!P_}g@UGw{5G3*>8u&pqrSJjAUcuoEL
8XCn-n&+acMXtHL(vaNi7Ty^?oEx1<<|+WgZ_w#ds=f%PCOgqFXUZyk_RI=1Vk6&w;;#`b4^Ji85
(%L&t@hOuW(gN90;lDzqNE+#J#>dYzjSm4)@lLS2E*BrwdE^;Mj-(~4#zckQjSNyg7Y5-E8&N_gN
uTu{W5{4lnK1q`9jlrViT>>{1ly&@R}Oc-UoEKwgtu@STLsR2rlKOmo-XwmdBPAJW1(PUO4CCCE7
sxB85p>!7A<5JGD6lJJzhO(Qe2AClsB?(1HFv#r@uY)q(f@A>|QEWWIuc=r>z2zvoWI1(JvQ|Pm&
Sx_vu<qH@=FgL>Rq+Aou#+=>fE^gV+n1FvGp&i-rljt%B|5Qy02eQ?Yz)SR`X8gHl*s*;MDSxX9q
BG<NCE)iH3r}SFZK%O)5vnVQq==bWO~Y4*1~%iKF<aiw9vn*BcL!GCX^%$uz}W*;y!vQ>{Kz0<Cb
+vY^=oVG*541{HROA^6TQErNO3U6IZx{2w3TIncl@#6@PzGl-;&h0Je=4+G;1L7RuB<-uAqcC{mA
+hA4b{W;*Reme4nGZqXAN;i$PDXV4jSx_(^*^U#UIYw`1OWvGx)xCa3Ie9TxRK3`p2WJ?$QydW}^
3XA|5)F}H!Y!v5!XtJVS-Z8zSzR>RB2`@yocsDE4so}>6W}r{pa_WvB<vfy;(LSsWygJ?a`Te(VP
j_4q3?3CMmPC&uS3JM*imR?rw9k#&;LAgyzP%RD^vLXPhx-u#p&sj>XsooL_E?+!lkO{W)u`6JdX
-jV;^|R$qXxw73+&JGx}IfYWE0Xtm3U~E$fp+8IzJf>Eu87T*^@Vo9)|~KIAM1*bV(2NYFL$y9Eo
K>L`=xXQ~<aE>Z0`M33?y1l&~p(;TLdxOfz_gqxd3rAL+HE>qpI)TUTqdYpsU$*~d3rX|Lb17(>P
LmP?fK9l=@Q?K#~ccyYFhYM{9MQo%nqYL9WdW#lT1aGMLsSX5n;-bHBlCRZTAvwgazW7J9>p&daF
@3}D}9s&y=4a#aFCd37>&J$uywesyPnI;--+Pe~H-yoT02cBR#)ScaWsOur}Cw}*)-QZ1TEv|W8m
vuT51rIm=r8Ra_PVl2TfBr&KGiMDPD7A>^q9U7>H3UK|W~i7PaM6%;b?NJ$VWMLuVI%pD8ha946+
S__X5!pw(8*`J%!rUww;3vuQ7THh<k(go@%{7i#fulwqlc&iD$?cM;2`QgVa0Pto5l<dx+q8d@vq
q0b>>}NFe})sF0#_F8Kj5$vnYE7Q7ZWss@Ds~tugDXo<xIwLd6H)aG5y@Ijag8Cf(HDH{WP9VcPI
;gvh3GG+&xlNV<knuI_L@+y?aA+6*t+=}ul;07zg}Gd!ru(^G|tw9s(lHbY{DT~qe~%zC)bLI)XM
tj7d+`=JmvS{Prms(Z`_E9O5wugRP8y2v6a&Y(Gp_V$QPQs^?i&5E)DCZ?WTA;_bN1?q<HW<aJOp
R>qsVPcv=qPqQ2G%IhS1Ktz_3ewk#oly*{IE<eE^nTDGn*jXyFzG~B`Q;U05LHK@fG+`rQshjJqQ
h=pbO#48pPO_+Z8J{=D4j)q0)IDvdlE8GL2H%O;6MxqZU@K1ekWS(4Vg>lk5^=v!k^O_9QKs0ph$
&{54jVV!!n&`^hii*{2mDjhXpTY>19O_i_4JB7xi6K&B{9QIy$5qD8RE_%n{^y`A_<10@KcF*stM
K$kb#y+`}5)3t2A(6#D{#W6}bQWp?xjCQftdMB{agoZH?&DY$sza4gGm7W10?nP?1k%SA-_Sywtz
cwCFXN{xo?hFG3bOl5W>_r?_dhwex%H93UyqFYJaqxS3R4g(`low(o~*a7MTzsowF?r>lDNbMR_q
otv0yh!fNak`_s#4^^Jp6<}(@F{(uC$ydPh(6&nGHHM(`1dz+vd7EI^M?ly<7;(*k!*^u2`LU-q<
E>{JWL$uK}!AFDXM71cuDHUB>GnbAED+Dz%{<aheLXJi4XVj;khY!&Lu7U!;*;c^tO(fxp!a^Zo=
F8A)nl%_e(>rip3^igeZRc45kBD2_gmj23^%9%12^o=LR7*S^?p57!kMIL9<L?eAzgz2C8l9+&5y
9RIKKUJCw5&3kTkCkWGAEEP8l0t2jose4vI8vzPBIi|f#WKw%n>0x%*1;UOLo=Fns*ruE$-JMxMn
-v+DUkgwPP{01nl&=@K1LXX4bWYmd9qwe6$dM=GHadHHh58J~v=DSAh9L{0Y&Qa(Y^D)}R?R)Sb+
K1f~WT79~#IRWgsQo1tKfmF>fqA2C86HC{LB(lM4hsl#LJkm1Hs%Yh!R3Njw}AiS6QY~+0I2b<Zp
7;REHRRe^E(t`EYspLgAv=rIlaBL-rh81>=zeAXP^oJ=CBLJ6L%6?;xqfe`*T9l36e}uv9pHM33n
nOZ%X0%Ne4`S$Iu*LahQ_&GB`_`Rm5z`BiQ9PR2q&Bu?@pU1=>hwiz~#GC*1#8vjj4y{pbn242;?
|0o3V996y2$$#IQRq*ikLFd!IuM9ZC<)dui=lmxm%7~P_yhix4_40QA`IfFtcFvH=)hk-sPC2|$G
WQU`{fmfhqKx*M$0m;?6HT`vc^<jJ5_mjTtKNQ0KM|7&b0t6tAJ@oc)GO(%)-70(GD*5!b4QjB~{
syR7z%nkdS9SSJ`cPbd8TiH1Syq#!)yc`13)zBB1fK`|IebD8*-sGcCLyqsMiozW5+jSb=%0MReO
?UUFTuhd!NLav3wsO**ln^!tExq6{r9xm0z0i8nNEg(Z0NAg^5d7rW)~Jt+)n}nq(ZkF3K4>beO(
}W+{e-1h6@2Nks;8_AWve1Kp+xm*NOzmk-f8URg#S1K@&@CJZ&vQv3ok94{(G!{0L5u`ZR=3)Z~f
gALBhejz?!L13}^Qxt=Ic80WWo)+l<W#(j4DWTZ%(5nZxpA(}`I;P0c19uPqUq|n=MpB^jDWC>hW
dQk(P2A|l!0`G1jcQi|eHW<BgV7!*A0xio?T?O>Q8}hQ~D20+@0~aZf2$QtHJy=y48}A~i#f^!1G
wU|LmbcLDJgd=Ug1NnlC|=$o5)0s`0ITD3EFO8~QeRsTZoIxs<$S4{{ZcbIO=4@2=F7^_o{%QVD*
*U=G&~b&)X4z9_$3B*iN0IH;ZUgfzl(0$f(T<xS%V6*?5UBSp`lt-7u8C_`li<9{?E~5OhYP-(;p
+skg`K;f`3CqQkWFO(ny5;Um9#%8Vpx#dm5~r%34pInZ8<RFs8qdmSWPYmGWY$OBLKZ+nU}|l-9q
6&|2Vr#IVktgql!aJ_D&$uNJc`-k#n{bmz&oZEsC=wYI$-+2wV&miGFTX~c&3N`4RVMFKKIY6P*t
UG(IrDfL=ogP@UOiAWJ!XUW#@C;bqpEh4Cue!In?QfF%jH&mPC#VY$hipq?CKb4uZU{}&>;2!Npb
gk{TQ=@4;O7X5o-M-w-)OWJh&;e;rr3zqlgcoAKLdsSGh=X)$*;HvGm?0W4xaxrpTPkd)1Ni;o{{
n`=(ti^Ax61ifKuIY9ze`^$eZ42yXQ@8AOok-iBE^SpZ85%5k`uK<p2X}uo034EnhcP-9{IJm*Q8
#}4aO<}rX^bx0P5xM6aO;{^0|cn+?p2s=NFL{_~VU(=ZuL&`65G<Z${D&4{+w>hg&e5Fo-1U7K?#
TEeR~_-X7u()v9ZT!i8}Mbb)nk8+E~!+5umw(2(%^>Vk$o0aXYzNPK1uxlt3S16CCH{3TataF_&C
?1d|grUEA5KoU#U0Nfi~mr9Ko%im74>O|L_XflJ>t{pGK`77WDGIXjZW-oe6O9y8Nki;dNv_wqz2
WS;QOB~%OD<?cyh>_`-X*9w;Aveq)DSShPhWglyZJvL#gbO(@E;$?nqNXpPvAgV?xMKJq$G<=i?i
BzccF3LxfD*X%ZaSSR15i>qNt@VYz9g?d^vqx6nT4LXwGu-|V9%4QEc;M}Pe17=6qa48k0)9!bf(
UOdBdupvvmL}4PT{ITGvanSEoB;1x1O~UGFkO<+Jq;R^7V;P5-(WakfUa(->jLsw4-+d8UraS*QJ
~4P3oaTOF!14ZhpALU3-awH(JY26_*Hgk~<-9!?Vy9DL7_`sGCP_-KlX5Hxa~FVLU#1{L%y$mp|(
AD`ma6$W7FQ&0xd?B66d1$ig+uUhM0d-bn$eUBt=AIgfljqYRL+jM<R-9Y&(txe^l4F^Uq&dFUTx
-|=v0;WCO0>j2jjD_*=VGsJcG#}5^N8iSQtX2ZF%zG6`;XJM3G*%-MVIo$3NILWa8!#ZzAYm6=Qx
%w#_IbDELX*Wxn*;W=$Edu#T=&v`f(||kAF!S<GNw&_K^0JAQ#qJNs2D8<+nEN(rO3qg66*(Kduy
*9(z=4Rvvn+UTwg&}Z~KxJhOvRR&B~w+lC?NbP!?y<rFnX|-oOx>c%XXWN<v8!Yh~FP3S3&YhRBA
EEjgGOj^ihDMOJe8G`Ky?n*ssR*g|nKw7vb*La*6wk@UihHWXT2Z`Vrek!S}Q*U+y80GoT?-e6nV
fG==jyWtt1kFu&)Xzc?;6NbCFgZqD(v6DKJv?zYB$dN{29rQgZ9G^qlU@dkh*FPmU7gPjeC0K~;h
&%W`o91=7bbSu1Igl_=h{7LLERnYm01T7?E-mgjG!%K2K!>nIv)Ntr%c}U$b1Wo1_y7ju;ln*T77
j>Q&ovalv(2WIDVvg!Gic+KXu;0yBAe7C&W`tn$o!&dobHI+kccz-M*cZdu%YfxN4l}ij$8~?RPX
*YnwA-h3Fb8B`y6p6)?=eU9qWma`%!ESrlXgtqX(5Z!1e>Mr|3oo+cN>q7A`Qf8bi|&wjZNYo}tD
E9S8tkwDlX=c>^O1MQsPHdmK|tUo|=T$&Lut)I)-~4n6wuuMtHXAwxK(h{^b_=XmvEAA8&|88q(q
qBqvSfbSECCO5Q6IV)F&1~o0sWwJIp44^~{v-u*b1+GjhVqxlTy7oOli!^c+g`}bg52pU$APxw0U
{fV_$=YIM#JFxOf{!H9!NGp04Yg!S1_`|Bha5eVFpf~Iqa4APoE|O^POLX0oY7Vk^yv=I3+wPFYz
QZTPw?+=+eu^1lm^2?LdX{g4;--SQ>S=M(GS+o5Xs9=o+4GUCWznt3ASApR-l@4lFl~Vi71P(iUE
SM5$m={iYw3aijb3oJT0esKUhR;ySf$>UkppRUcqtIiS~xtX_pkzR>&PCVG7o=3Ud6n&E*6?v=?;
A2_IXmuKg#!V4Ms8p~Rl^o^szC5Rkn+4Ge^=kF2-2>v}-Ls~moZTqO@I{GR;0a2dm|??vC>${DXx
l4-E76wj;|{lFmsryP|F<sA<X_f$YkC*lCNxVJy-?C%dX3By7amYS1f7t#LgCcUeWHRJGgXg_eZ%
oM8kn-t?|uEdm+G85oyOOrzv7)KF%K>5(+GP?tsJ)NbE7MIy#ma{0A0(ZXs_GuKu@j!Xja1YgK{f
9ucA11x%C5I)eICLTg=4(v3oJ?jbG;4UELgfJlngfx6L;594i|UJLnl3+}cuP}u6~^ykx-2h>tTD
ujyx%#*WC_2@nS}mREuowpcB2dAnhHgkO3<U)ZwxK(f%HTtV_cn|$S8lFPnIQ0WmFKu3fH%g5TNO
KDeV@p&OJ}1$zZQAtiX!En2+?b#;FOM5k=U9lt@4^Xx<2jn!KQp7+&N;HsPg+101Mkq`ad;4I-_A
ptsDRWVT!Yi4L?6RH#K}H>Y?RgM$Z1r9O<Rf3C9Zqb<90+q=1f{UOmI1Jo+&_XdMruiqQ)<ML*7u
A+-{Vw5FI4EC!1t{sA4BQ0>fu>>x=Ry4YfIV)6`I8Uw<f7bvjs@m9+_m=RedcSDFDtHF%=$&+H>k
yt49Tf2au7bA)jDYp%*;2f(2=<Pcjvx9D1_%C=;l6s}&ril-`iO6wP7)(Ul2?b#SL<m6sb@yjY||
Q_7F8vinM;cnK+=0Ny<itZr!|*F`!d?wNHs8DxrS)qF03FH!TWe{;8r2v0Oa7;R=C7R6V^m*BZbW
iC4v(}6ME_pEg(VKO@C=<O%(dZQgjF!CE(yN#oK(PDN`bV)t5#whJGx=pBe=Oc1fKi$H^}u2pWsX
$3_uZeJmm$ts=ka#k&_BlZ9YSp_t&_!I(%LPsD}JUpe!Uu?je8w57zls@8lBuu`ezN((}y#TS)El
k;p|E>&nEdALRZ<_yffP0&4UJ96AD<H~}>#ga$sjBtHDcQxFy;wz`Uki-G00sMP=J{D8Up}=~r17
G6EM=<_tq{G0DTH{hE5ocycc9170{j(FzIf<f2e{+lrxcq1HI;BY7=>%Z5GID(sc#H*<V^TGvF{&
%zr%1U((V*)o+6r(zk(=d(j>yh*D|^3Bvud);7aVYzBDFiBe!AU{qO$5?hrMaO#13NhJw31RuQep
g!f}Ejr>AL65j1oaJoqs-iyWnd3u6ggk76qCB&~Ok)5NABjmH-`Tm$1IY3;}h!>L-xZu6?HVm*AH
ZlhT3812jy!7hmN&I%4pb_Ce6zUUsJA`z&qi;&&Vw4A`w;#hj<?HpfRc}IXpiyFpqBKk>wM5YDhB
=O^;vPz!ZRZq~77G3Sm00*)uqWD<jZe#_J%ow;n<_1y8Z7#=mcU7IuU)<*8j$1~}#fuQBM1s|D^S
?$DYIraiQ<!WFN>8zmMZV8)jI$gQs1QhQ2gn-flCyV*gNkFf|Ml+mE4Rm+WnO!#s{aeW|L4Fj<Ef
+Q*Wa4#l!jbxATS!Led57BV(nNx6a5A%;MF6#uy)SE2Z>tzPn-*CK$)m0NbD%tGfqWqAsRK{xe!A
jDq%;P!q8htKNPfRg)XBi!baV|y-5})h5B-K;uru2=E?~q?k`opYIeN{O<O1r2ueflR~($X5Vv0Z
pMjkQrWrB&M3Yr8?p$Fkk_>=as{sId9)iY;t6r65AL2%^EZIeP&jdHeiqQ6d<#@GNB83?*I?-w|#
xSog9(qH`OEAF%(?maaR}05=<ec+LR9C{Xr>pv^M0wIrP_hH%)5)@|fHnAgcM7z~)yPgzf$1)&1+
kZr^b{hTuya(n=_#T(UCv28)FG7x<zHZZJ?5=Y=6saAq8B~o#1+Ezck>F<ABfQ*WynB54blo|Jrp
p{fzIzb6s6L*2g_oiTHti&){RaiHVbI#0M(LkosYpfSOI!-O*dm1fVFdk<;UguFEIm#5MX)}k7!U
G&4nDHxZ2&>zopk1+#^8Uzkd2(Cemu9X@6T9(=lmEI+g@p0Rq~H{^K9l^*{cB;-?$QXMu*3EF0~p
15>df9}}!4>W2Wb3^O20#ix}+=7~6)o^e7EA`Vf3R4%#{#JmI$#xybchb(%&_ng20<^*L#sb1D~I
j6GJ>owNCm~p^7EuhqsMmgGwV@J^0h;GumXo-s00BoRtxy`LmSPxzvYkR4bBI1EjtY@?QT%ih8Ub
+2nsLFxmB}3}Pya*8LA`?8~S0@gid)C^2DOL^lr!)Yrle89JRT+$ULmeEb22?%R6Pu+z^KLA2t}H
~P+b{^pi(Bsw?mD{PJGd~v82hS5oB*G64b!mXA|_s*4B%|(C5I&r9D+8LC2%VBinQfy8(A@I+bwc
DM#AY8+9#(oQKeSsMaM0ZJPjTwc%aM579Xyz$BI1Yy9=+G9A|o#JVGYf41LHor2?zb5=Ky3VJ3o9
t6Z*1g*2kpD4j}5l}1Aec<Ok53J$>&Aa~H*6iu&*h*5n~cr`tM$7CQ&B_vS3kU@Pa$F1}8J__yny
@sEL4{Ws$Xe%<Yi@MRZU6nn3)Ctg%7*B;{`9<|RG*+mGaVm$MXwN5D?-7!{u6?X(kg1KuGzwK&l(
JjDIWE#g?06Lox(L_P4u2CNh@@I#^n>p`F>Xr6eG{4~g_DKhpX6s9=PSm0Z9W<{J&;;RT5kt1{mF
y-Q~Nh>1Pq49gF}L!EnR^E&GV0L_1tTWXTo9L0yr*dl5b48-E7NR0I^2bI}GO(voJCBNCQRhBYD~
&1^`9-#K1gVj1h?hZvSJ0W)Psn>Ie!8r4+<-q(T&M0Pr#Q|3Chrx?&2z21VrHSPcfWG+g!NO`$wS
;AS<{LS24MCf_0mB&L<za8U0~g2QwH<ic!L!4ROfGOAW_)+~`C6APO!>kXHy2OC9p)3^ph*KYeo`
j-@O4E<|<aHQ>iMWkyFReA5j+KSch>~V@{ZDXl?He1bsRM~Nil(x3@QRYUyhIx6zWAlHvTh5Hrsi
T`qHePT<De|Eit-W-x6aavx7P*cs?49Ko2KHM$*TT&zY4ZL4aN3(rxf6NVzVUj3|0z88$Aron?l8
Wt7Af<?F+J2lAKl0bk|i|q^Rqc=2OlLP8^KMk%Ce$DN{z12<oD?vv8;1#b5V%58VCLrCQ0l`SqLu
di3Aj%uE>$Vq6zngo{Qvaeom&;&2gAo!+kNj(BMqw8P*Yn+k<kIQaFiPqU2$KI!P`X)RX%eq+%_n
L`xqS5+iI>+^BEjq-k5+pu*`k`bv!u$zr^scw8eHDq3^^OUl$XbMi|znjl+;HDeQWr0idgISHZw$
TC}Gn1D_)mr`GA+QKZ8)z`2zmzW79qtJ(x=amOJ&C$>nAInf3$;t4LHD!w#@W8mPnF3IX7%!1KaI
C|9qf;A+#}RA>30$~6^eybzm!?|Sj)ow6b4gNTfh-ARx_MExyC&+OsE?z;aGlGBR#u0-0ueh%Tj&
=}X`FP#b~X~;?|*f$t_Ko19jR7M_EjutoS}ccYrT(h;C33O`{alkWEC|g{2S>{fQ1g5;bFNNF2w$
5ZMb(DkG4QyFLSPZGTOt?O7aChD_<kyx^I@H4?XeHJU+q%dz?N1h))=Gf<D#5eTtpVs{XIMAR68R
1dVW*6OwhH*3=SwHFCeg=daF!;Ral1dgil6W@g4!l19LaYch03lkbZ4)byd_s<)+i%K>o?<X&v@S
}rRRfT-l8z2oKO3S&vXp*OLm+dDD{z0jGTF$0iBQ!L{psjj}^xQAXkosLs!8UUHI4I?lwvwyDgrP
x8DKjmxz9R;!wZ)}lz$0pN>442nbCj$-rlm1ezF9O8fyX=|lK{4Yrq?hN}@-kBbh-Bk<FfsCuo)O
*EOo-!}A*$Kf!fHX8!${SUU8Jj7tpt;BIU&Pz6wCM1ojd;Xah>u=PnQka_=ddYWZbJoghwJ5IrQ!
3`Egu+XTb@5j{$RK*34(QB!jkj4OLnCfQBo=Nz@hn!OkjUrJ{r)z5)<SQKmZ;DiNhV4A6i)Xj_r0
J>5||s^tiaWll4>KUG>LIOYtNK*Nzd0edhRK!JH0hdqo)p@RAl?A$g4n3ZT_YAa{-cwOa;WnQd?h
1wADrMGn=gu9?!$0kj3mmj$q6R?znf2niH%F<MjsfgN*lnMIEA?6`e-5$6Ky>!332V{45cu;YRM=
%>|^GHqW2-(0kV7(vd5Z_jkVqz53^V6NzcxNNXhX!rmyNP4&B=)(miRaA4nu(D`2a33WbJ=rmFY;
BPnn8OoU$tlFHHYSf0g>Hq8eId8Q#D1C<Bt4TI}jX$!;ITroF-|AUW>ry@hCRRWgO}a2kg}_vN{e
n6N)IL50Sd_=xg8vMB)}rBBi-m&A3YFXsF?J@QYTkG$9Hg3CGCG2B5;0X*7NV7V2~W*0z?%D2mj}
jy;18*J(=H)f8@)WlgwHRTq9N$An%83ga;|(&I7S%j2<DYw<OGT0q?$U?-P=W5-Bt0`j<ndwu8Lp
B}8L<%9FQc#sv>(SqX5?WwfmFSv%{g?>6OZ==0~zPh%lA=XHy=);!I%F9)zLPK})H3^=W;(kWS=M
nTMK7h2{<vaQ%l<i&*`xFDOF5!4yQHn0$Ye|fCQ>whxu>LDzAM=`%r7Oc~yl<2k>pY`A>MKmjM3e
_|dCZ+GS4A&U+1?RX&tQ#Ci{p3CUcSUqi`5bpnIlW=O42hESD;ey%mD<TKt8AW{ami1X({0WW;3(
`XOm<_;?tFA*}5Z7b-^4*SL+^hr>6z=iYdc0vWxF_mt|S2+2$%<3v(<gd|;LH1=OWoP-f;Rc7-v%
Dx>G+O+m?O(2_fPo>d=!$>GoCgf8W(7rhaibRM)`OX-3{G^>L0g5$cOT_@0q6G{w1-ex=|#iTOR%
=c`suCAllVy|b!jF03JJ1rhxuJY-V-Z=(r$<d(x0g01vWmJ3kGI|int!x1qaFJC`-pTsmX_3yV66
4Q&s3e6~c8gvKIeK9*6@qSYm0DgT(5ft5qM?2{&v*lI`6wbrdRkEEMJ)6oUjS=aO-d3SKs!Kw&Nw
i}als>y5#pNs10@yzFtkfAdP*35Pi-Wj73LEO^U~^wjY`2HU%mn=%!$^eKqUGsIb>1C0z2i5O7dQ
&Y>5+895O<STv&7rdeJ*Oby;3%F-MRzupI79k`Er|p6^P%;WEK~7_#rsy`<_GiTKDu(c}@SoY0j;
t<vHdrTA$fu9=)TSJc<yazv3sl!d(LZgWZPY4hWp@soD+$11&4l03$dk&jKAq{lq~L1>X=OLPu9s
uJ|DzOBc6hPvgli(vc&{o@e^@EpitTU%d%`T6J+{-L<aeS$90IIY)gZ7CB2UIPyP^OtY+wZ(8$^8
FRX!aa;sf7vwAHP3%>ujfkDA^{eW;_CK=bNCo~dh*~g9(CkzR3pXgE_(U=Ur3^n`7AFMJtkXtJpM
Ui&ZQ9O!d9WYMh|6{&*5~xGC6Xz6z3IVG*z%DyM$u25gDhTD={P-K3C;<;q<ZydZ4>SP@NU#h7xJ
;Iz_~?gocQ`TX&i-rB!oY-8(M2EUiUv-f47b{zj&TvW2{^`YL8iFp>opnUb{Nxx#fA38P9;b2@Us
JJDrUVs70#yFuEh1uVYpoV38poS1e-)VdHNN?@?i01V&YvqobsywE+*tS-z5X<tgoy8_;&Pk5NGF
@~ZJAWc34xc=ywkG@&zs#9h5)f2c!$!a8e%OZkGg6c+ly~EvJ^a}A^zMOWUVtq%98ys~y^*VW~Bq
&hA4gKIMt*&PIx&BVZkm^fW>5ofOrMg<x`OJJJ@tpa3XDWT9mQRb9ub#j7iPCTR7by<z<@*;uj9>
ip{>7_zFJHfUhen2{J9tBi&6`Lw5|rH^n>&I6IpsuSp}QSGpCw7h{VSN*ljZn2y19LWQF!UpVOwg
QP(A(ak1wC|76KVT>6bYAaE&ysR*DmID=~}D0gRU`I5TL>^X&Dj_s1_^y?8tR;rQE^&nTR%N;lWR
{3B2xl8@iN{Ob$(_~zx?cQmnge|h<43<n7(|0}Xg(`>AWL|TOLcyTvDFEFHwX;m)snm=6w<DeXsH
BxIzdQNx#pSLfb{rv3v7rm!1UvY8f)1tqYGYmKJvfv0vnDKPyx6|T><DbUQU%Yw$9SmyEu{y@HA1
fkc3`iiL7k()KN2D>;=wXm+Mcqn32F5^0Bw8dIV}{>jd2GylMTD$Oay`o`d+fHwr!KA-GP_{2O$=
Hav}9I$g8p;x$dZo`?S(lobt_JoXi6H~w5P7Gl6A((&KQ*X%w2iUz?m+AJE;b!ABYPy9r1b!d&5}
yPOLrxfk9bP+ge6kOBhgIESGp@D|{Mq?N?)6l#95Zv?W({?QER|V8H_lM`pxS-~r}YV0!rb)usR&
iht(ig;8pObff3OoH=g{<ax^YzHt)*c3%}1i-Hj!`EE)hdvIuHjmBXNE!7Iy#wvP7MA7@Q#E5(ZX
T%SvTe|m|^q-^y)hvSvJx}-h7^#dZ_N+r$l_XK&aXy_UUuR;+3$G{?i#mSDlvvn+`ic1P0h>L!na
0Y=?_TsF%h=|UtvNC3M@*Rgzp**!8c066Zl_D2s-`P(@UBE}&uY8!LN%A-b&Q&~bcU489Z^JhJIk
E_HSi?p5H2L|Fea)ss_*KXTv5AKmKC1JlxB(y6VA%kD&g}cHo(V8LmH<_<rVBUml^r4*nU7<6!a8
#G4}%<(OoJ7>H+bxtSel&m|yH-A62$sZ!>;I7Ij&%xhpKCeb3AUR7SciD~wtuug3b4kDCrH6sYln
2sGxg>8`)yTjb^nNj4UeT$qprWKV8!uAW*_EnWq%fEEkf>&f8Ew($4Jl%`%02PQU04$f>^HfY=XD
}cF~Z(bqI@jEuR-=`6HREA1lNLcjsJHnvNQBed<XK|VEjG6B5u;9URiC|(4aSy&&H%*1$0fwACbF
L%R4M}?wM@PUto3SCQDWj_hN~%zfW8qf-iHgvOu>tXxC|{|VL+V9O5z&faHf1$O{>9mPM#bBm#y@
b*P#ZZWpM|#L+yi)pJ0O-5)*}(V`sRwkC#xl*qYhwUw5^~uB=gOxcazRO1c!u0Pe$mzQ_+1FPpK&
q)8M-eH=oLdVdDg#KnaFn{ie#1MN_ff{j8=gLti^tv?JBa)eJ6AEj>AkG;JF4q|&oJX&Q$b_}2^R
8~|65fJ~PPUBShZZTedk`9D{g2Uv>oqgGwOqF1trT-UczriVI?f}zsn2=e>Sb;08u&*4VMWy=bO$
%;lkf$rJNr{rFUH|b@GF5YMXJf**M@|lwH**|T@@{Jf(bpZy_CAmLOkSi%FV-ZD68r$edH+LAt8+
reZ#JJP`Kl&N@X+_VdEfK*ZTP~LJ*y0ye<GwHgYL%v02{({=gX?N}jR8JCAmX)#lcNdGM7koo9o4
`;m<~jxE5<bYhmvpZp#@h_k^9o_MMhpsc%%johV+JmU!d~c3VvZ@Fppz!FfJi-6|7bK?u|cS;8qI
T+rcxuS<n**qv50|BoAL+2<2#XhhQAM*-$=#W57ZR3n=S6zI^Fx-LQJprbAFaWG~Ym@E-xEgB#=l
B&*o#iel~ar-A-7)SvwL{$Xy&?7vE#M*TT4Ec9gnyE#VqREhayPy?T<k&B&TWB7Ob`Z>#HpWxidX
VW{C+`pr47d#?0&6SL*jIpU6W0T|DGj4nzIFYc&*L*RpIcLsg%&`wq$ljxmF~H;hick98uhQ<tar
c|EUk`svx(JVI5YEskXfa#!F3Z&-9wf8@;ztE7lYa)=epz;#vuskwd?N&i4T)q~YB?@pF(bhqp=Q
1lwP8JBsGVt=lW55!3{`=bkvAR%#vGKjL940<cx{qUL~0w0IBS(o)DCu9x3;4r)Zto7V`r9fc%AT
pi!0pY=V8))$ISyt6t0jb)?Fk0_lTy8laRq#ZrR4^9-19&2*MMbhFW$sB4&xCV{6hpHNF{)Ob8lB
wh>82wL4AHvYm!j!(keFD|)kINihRJ;~Rc^%g8PG5Q0x#@MvGsHRIoaa@fx9JX3U9=x`q68SK(sl
TIWKG8*in+(bYYF1Xn&x&$l~t*SPLul2mi;7)f2L>_ir`y*BTGON+PM%Dj=Cq(xNeJQg9iw;w!Sk
1$cc=ocZc|35SunB&_6hPYopu2&3yi7>bIN3Dwvyr2k1mp()#`{c4beN@R(N(-*ib`16_8lCr&i3
_Lp>5r1@#^*a@$p}e-ygpv<pkfdER!>81})i<M-f|lL}=~-gk@2){(Y9ASu~ozrUeN{daQUMtwmw
%PDJYfd=7)FJJPALZ6Iq2*1NxZ|IIsETeQ0%&Bgn?o{@RB0Emj*qs=Oqx)g;6TWY{HO|?c*uLnb;
n+%o!8+Vizn=}<z{`t#yZ@xeNne5QeQ0sPoFd$*sV8{_iIl@!__OP!A>L1^K(;XZ<eZk~B4MiGz|
MLC!FHBQ|gRcfGc?(sSI^VrGe*OYC&2M3sY8hk#H0<EuJfn2Z9tL^!<M&+*zep~*Q{97vhD_NB%)
7d$#w-oiddBVuyU{>AL@Dz$i4oJA6L>Y^*TXZ6rG{DPPjCBu{$=~@Q>mk9=o~9-0_&gk*z_xAf*i
9EN!(pSjrW+8wnQlcW#bwbIwV9>o1mjlAWT+Q<qZK9LypOyg2=%fE>+%HoIfV>qJW4;j?By2=wv%
lmy@mpTRa)<pK0NQ2K2QVk;<is+!e(QXz%zC=iTE71=us0(@R4Pliq}BV_?P#Kxw#KVdT_1YqCOA
chstIsrhg<=BHp|T-6uV7%v1MZY4`ByNfhoM0WZMR?=Z6SllRJZp+o>6`9_!S0;(pl+($PvNKasb
h4j7O|!Ts#X}L`qBfA80M-F=ot`4rd4TvP>8(j@1vsbQU$>Kt6Lms>kPpcdE2~uhc5mNuB9Yh$vE
9lpM}fycjQ>raxG2&qgt_(}eWiy=4|k)(=!qHi@Aq~2&WuwU-ZMjGrmB$+lCo4u>4zgVo=|p3AwP
wTT59hZz{TxLtmb|pP(Cg%Vp6@^(?or}we4iscb;8fG6Tu2_NdRfV8t{m<s1ciIAk7Xw?|?g((to
;8d)S&C9GSv;K0Mm%c~ZLwZ&bpnZK8P$a%o#!-EGf=i_5cb0g;gKG7=l)r95LIEiVKRwtomb`2Du
Mn~3~@$QLZj2)}`YE^tt$;PPKh%4{Ph??$1RE5t576@w<TxVD{9k_j{wq{}SnIkL;%nf^#>IttLo
S%`)QrwZOhstQLC@eQ(e*(NY6M1AuG@ztzDk4Mwc4)g!k)`mAbZ9F1o5@;dL9;F=WH5b3m>wQ(qZ
c!6H!!y<ALe`RY2#6M%z8c}H5%(;Ppe6u`<J=}H5+jlHO)xOW&0JtdB{O8?KdN+Gi=KlD{D#pmy+
k>38UVA6T$+FDErqnj*0>)I<*?2Vi(I2Od%lq3~%b5AayLTF+Zv~_P;BKNM*Nd93KL9j+muGYmx)
o2nTfLayxu7gf6n^tsJ(5_>kC9CzzYmwx(r^S4~HCh!sGL=ul%53Q>@|G$<(~DP760b_g;ygllTo
tn+)53O<cg3^HS5#cny*Ly>W~G>xe!orf_CFQXJW;Yw#`ts;?z*2N2|)&ts?RZU@Quw>mRtng<+5
{M`uDjLY`rD7$r>iB|9$%qNl`{iU7RF(|PXH9?+EIfOK5bc6(5L|vbjS6r<%<PdzxC;4&J3Qz_Lr
3~12z?Fh*EsgR{x^Ka8KjSzC&0BcP-f&RqyVQf#iz6YIA+&k?&tU4zI8#--(_odW<~TzO!8?;se1
C(hJ@w$m_%i@EC=C}kPQo-O)@bwvVrsLGA{~>f?o@+MX=QX;s&@QA_JAQWYAk-9pi8=v3*I3VdVq
*fNqvWr85_p%(s>0*KJ1B70V1E*B9xO91gl<0>MGfR&_7>TaGEDY8@g4cq<fdXJS1r&ahQRda_bG
i*Ra#W%(f!C$WG^N?5r7;j-6vlcX}E^f($)awpBOF|W*^u$ID4t1-o8Mh^&N9<c$gFFZPhG$PTCy
4*Bp`0$Js0;fCY`K3OmQ}LI>-->mh;zPV6`P1H+LpH|)^rn`Y`0<c6c=*vYgU{D804l(=?(l#@OS
yBT5f7a1RlUu0I+ctmPH|u)`~o&f4+K+RA*&NRPgIL8d&O<5Mc_p1dh#xtVO3nW9>N13MGAPhi@k
o!stgYjTS#MPUt>v)W~%LxKRybwXAbf0Gv!u&n+BgU5PF0bwRAF)l{xD$NG5)iik5m(ZDbZ!FKVD
EMRBid%5GxRvR{Fw>$0Z&Jt{T;b!A?wwK=jEr>WndB@){|X-a*g2G<8c$S=$u@_53$b)c#lA43sU
Ph0_<3o}|dG35YnQ|L@VBA}~)E>TO|B%N`93_RAcb;xocW#1)qYa$_v6$(~}LP=Z9mnQ%{#jx@$n
8Jh=BGg}hvzJ9^@dkaQ6GfFDkTCdQW<X&f!uPMSv<Q+{YAqH*V>GE@zVqI^`nEv~I}vcm_rjiUsu
Gs>&{!;Hnd;$J(9r4W5)BDXZwILg_oHYJvTp1S)}b4Q0H@)XFJ3(-f7RMFMa4F?B@YzS!7|{(Gmr
YLCTS5^oM$>rws_*#DPFcZu!IrFQTQ{~qFY3U5yw&b$n%Wi3Fqw6V!6uU%M0|+1H4XpG>ow;34&y
)jpv``SW&@6N-j(cnk2jd(jrx^7&qx%FZvFTHBn(G`Qzq1%89I?z832lN-T+XyOl){5hX-~NGO<0
6A+kSNL<T4M_8XyPLu9HC7FTWkE4TqM@hY6S^U694ox~S^{jBS!e@-g3($rG>&Uf@AKS$&lmS`3q
S^zPMKofHb0jm!4)X*|9b#4}ms`PL)@FU1ImBD6KTlk?>I9=RM6uG2CVqGZ3*C6epAH*n9S%~tv)
aO#P#Bw!AYY9U`>=*&R96<~6Jm*3&&Ab_Rro7q%snB8ZizF9O`r#^_<gZHjwx{>zY#~OMOEfkyx^
)c_G%dk1Y0gGMnBr&AXt{;^lA}x1xzguC5C?~VkmumJ6JABs8hKnCr37b3Fn1(!^6q`so>(gEaq0
3G2y&9(!U+#A1jST*wwH~5u-uH-ka--Y&tv2${ra(^hA;39b#quVaUs5ebyFZY16dA;NAj>PMXT4
Fx%@ym6e|SN*a}W2727NNbR<BxABdS$!x*oBq0BC&nUrq`#7?cX``^wMvE!gx>aefhM^nzWH5YsQ
Nqw1Y!s0U@tbd+?S1uV*z5J!<E5&b5#jF1sfC(U=i*}0#Y$bMMF#<0u_<%{bG3k1t7g75a&-%s!t
gGf^v`-Cd&Q7GENnv6sspbLQ)IF&$A(3MqYRMNwzXBtQ13_u8%(y|5T$N(^}+^3ewU6BN1-sF#B{
M31B))|_~N(pA{+DMVrt2!lm7;HVtG?_v7o|6gjnXlUMQz1#@CJx8uLYv1!1*1kC$JZJbp4d-Fbk
XQUCfMUy|azixlF;*%!*bjTZ)vj}?m2YX)h|YL^$COe65U(z(MU6X8oO4!l1Z9U??|g>=3I>~%T@
SdA%;qj>r^Z@1;D_(Hj8vy69YT?QQJ+uVPeW#Hg_wgBq26z$kI4^duIHbl|46dJ$q^R7p6lEFYni
B_y=l3!F}XZ=n>lC$}e_QayN40t&%R_aOvVl$hht14?m=~V$Rct&ukkqs9`>S&25s8$cDy8vab<y
`t&v*AxF<N24!t2wJdJfKiy5pP9%C%`0LX0?y<H(jJq9aGcD#nvz+Q^mM(iX|IrVcoEtd&Mz<!~0
Mg4n$H4*pPW$nG^!(7v7tf*O_ZQMj%e6V;y%@xL0LX=C%k0mvhyd9ip}oecS05yOPOlXEdT$NF83
PY|*2DP{+nwH(o=IvY0q6)R|o56Hfb<-XY(FAdlwHNE<dOQqBI%i8QC+4e(DzB<Mxo6IIF(;sgvT
FVLYnE!2D^;>3kU4;?;<sSYh85e?k1I7(#{IA^W&VAB)jB<PB8y2BIN@l0wltU@D7-<lSrg2gUSI
F9iJ%(#jrP)iews(27+8aYpwciIbG=MpsGCLHeyo!^;01;c!^Zx6i==c-T^B@~GT+cL8~p=2QO9B
IN6jGJ}Ftx-rP>KjhXKF0Uta_Q~ba$Z&dj%R2Bmh#&(FN~(;SIo>H#>%7!l=dr?mk-|QAZM`BP8m
DpC3$Pe$m}v!Y_bs<s;&!}7F=()J<bIoc`|QfYHoF%wC~jF+TJG0+kpX8RZz*kH(Z^uP}(=PwcEx
J-$d(e7gRi1(@c1k+NPuf%+sV!LUHGVEuM93I~+28rEE@}=ngnoV0p8QLU*D30tJnI9g2t)LZt9Q
+PuIVSA*U`&jBww92B{gK1p9ztX2&0A)%KzuP6&)=-@XJ5?J8|B_UIJQ*?BE4^I?zvrIXG51ld<6
O3e5fHo9D6>^3G`AB#uA&|cR`%ls2DkX`S_CeL*O}jd=wAQ&({4|M~MNZ<PT(ia`atY#Yw3tR$5N
QEiD`hc}&{;G9Xw(Fz%0g*|JURdqio<46d;%+^l@%1rjetc3tuR>BfP2$Y5uFiugOw%)Vrb+`2&l
Ya15Q*p1<oI8{E*dKgpsy)7jX4q`tBS<2A`3sDFwdi0pJg08ojIRcA8(pC9UNXQky2r^+Fd;dkRy
|szLD8=E|<c{Hz2(IQThw|LxlcE|_+rUslu03<YgscS$0qh8xwt$@e_gD)~<23tK<Y1)Yxgn7n+e
Sy@Za%f_XxbR}4ZBK$xpjA#b+x)NkvXC6V3ij^rMp<GA}Mal0-`|#OQJ}B$%b-5mbIu(XHbs-573
{pJoCcol{{U(!%lQWrO>7hv$rT(EMCY_%}mogSr0#eLlRz`zEXIoTk|I|y?%yygrq|bkPFO(D|Z)
W){RZ-iiw@~;n&ceqz-&L-**NAfo_d%b=WI+@Xq{$%6jY(k0ib}}44q5T5i1qVyA*tdfWmRLqBMK
Iw!g9bto0`#d5fV6<#2hZs95~oJOqY}*{Zhkg?cONf9=wJ?%F6)Z7KvWW7xf)4l&Bmqyi&yuCT#p
?xtDw>${V8RF)j(-N6VB#`pSG^mWpakQHzrnAE0y{q}H2J4b~*5(Fc*@wug?UXS6pf>tOO*`%oFe
NzPQ#%%wt2NcjwxN($T0dCBmF60r4e2Sc=U9PDo|{kqAgi2SZ7V4||blpg3EMQXC2a?y|<GLD1lk
Yy<uG*GMZ&29v5(WVL08X;X!_Pe}1PwgvunvJKowPVPsx;pE)Q{7t7Xj>4Rm{q6H&$!f|+E8_qE{
>f21=2n(6iy6#I=AH*Z(lGcK*O&<#3Ft`#)3dp@9jvfirLrEHY;QnV$@t3x=Uee@Fo7;&=Mm+#Tt
3rmTahu2U4XqkfVA;ll;vyPQ~@Gq>Pf0hcHmQ=B{wAS`#`Iplt>S2}73hWx_D7?})$Pu4yHs=Afg
$QI;18Aj@emk@8pMx5367{VKgPVHOCLnh{JS-g0U(BvM2^M5i6`N}8g(?+q)<aBuLPAayiu!4Sr&
#1pn+T+Xuen(X$pew@g!Re>R=kl+dt&y32q#;l(YTT;hufc{A!?Bmr9wFNIDUslfI5XRorf<A*mq
`SVZIjuq5yy?`izpi!ST)d1+eNGZy?-<c)+pK40jABI9*CbaNV4Vbaxl4VF^fyJn3UHt?k+ypX>E
fIE#h~Nb8hxa9-7-RHG45&Va8y8v{+XSAzF{!baI!S~4ZLFesfy8np%~SQ3FU|<{tk~LTsz0ZzGK
@mPnRFabYwO|KShomPDdVFQoJ&G8DX4ZHu@T1Rwc{0Rw?eMP6HJF9Ro8jR+O~KYG8<wq-qwmrW3r
PD7~evy+GRavdG!Y28mTNaMlKj00&n{+nH>2M7drf<+my*G+J0?4_l85hhbHecj;qTxK<9!w&z^q
Nk$nX28pD0;Dz=?u*+yu{h?dmR&L>4F$TVRk;NP{xCJOuoz+0HmLcy8Jm;*DCCvc?Dy*Z4U@kGq@
GPfF@?Q|CZ;OJuA~R<=w4&eubGgF&T5@49r-Yj1Dn*fPSA~3~n2K~~0hduwiOVbHzh^SQMK=^<k~
}5znr)_4ZlmbOin6uM?)1f}E!L5f>G%PMY-cypgprC2^U2Uav)N4L*~H*R=_1S$2r$v`)<RD%+jp
YVE1gA8TpOuoC3N#s38w_-u|T}ksqy-K6y4)dw3C#vNuvs~q8ghLe2IOFULCx!DcU=pRY{kJA36S
F&lSPoWo70eDWJ|0C-RHlFU?F#^yq+0k;$Y+?mlGyYzd7TmaF1<Do<r;tn8(BGQo}t0S$=b21ufw
lRO$>L-YvQ3~`CrFQtqM8J1FHOjSly9R<LkomIujrHOYHnWPHtZbI_|5i|KfVe{@#!q^q#If8q{Y
b%7{nsZs`8Ecx$4(rKhQ0PErrY%QMEWsm0u9*(70wUd-13i3Lk+D`QTGbfi<0daErz^{H5C%F;@2
u=i6?-};fdXo+o5w}PJ8PK0TGA;40K5iRbi|r&a{q8L91vckbO_=#VRgnz<8w04ASTbrCP^c3?s1
JPTe5R%J?8l=TW206<(ggk!eAOg(^4vS1-%_BQdK8<iIN-nOyy=DZ+qW=<VVRm*VJ|y2HB5yqOsu
ju{b@FVRI-O6S4<na{i~I=+Q=lF0}<_-<zvGTEl+Y(ecrN)Qj?`B+0VUG*}iWKWd;>&Bp!VnIC<w
nX@vd?PA|NNg7UY*H5S=&#KfmmL`>LUS*cv$3@O>iKP==_ehQ-k9sj%Ra*PoQAR5;(Tem!WC4wwo
-I8iT@Qs}cNhrjmy!%hzP1qz6TgdYV1zY{29>VI-<m<#l?FqV2np?Vo)S7aEy+rP+LmSj?R#*nYW
tQN;k?Nrfsp69O4qZ@9Ab&{mi9tAptY(v2Xs^&Kvn@n<tta<BSjiyh%vEw+F(p3G`1?iTE!TeyLq
IrR>$aO9JP^bC`Iu6m1Xw=Mid<o18#rJ%(KDSZ_N3td}iFh**2=Gds|WiBT?#kiFYx34>w~=rIpz
hoNIK{#cQ$`y=bNbc2Xyx3ra_|W?h~tMG@v#VX-qFEi@{1Z{v>sI^eGuR;W2gZH(;@A78r!80T6c
!lRNCT3K?Ods;cb1iYMZll0eEdMmPDWI8VWplPUk1okC{`9XqN85ElJAqoOHk(n_O2eP{sUZjcZ1
bjA=m1+R*-MtqQZPZky&`^YRW>!lq$hB_eo@iGvJ&2((*yz@xLX<jQ=To92O2+I+H^w9ktRpLG6k
S-eB#uaMO7mN(CJR^TEZaX+4YopoPx1n-iM<BN(Viu7bI;w#bHeNBumk!8^Cvr&C$iOkX82F=f}+
~S397{~EiBJxj+$KfgOpZKHvajDEn(OSwZyg~&^cMJX?upR{g`TmX*;3zU~7L_Rl00#SeM?~6>xW
;eHT=f&}?`&R0&si3$MbLPk;;(E=jgU3D4P+l9DZ=0LCSa<kW_5D6Q5-%%HxkE4hJS5~oH#S6P8Z
?6Csz&<UZdSPlav^OPWthFaArH5+S1!RsVKoz3a4kYf{Dm!jmWgXxE^f);wlZehJ9A-w&q?_S|Hm
vC=A#<McZp}oS_0rbZ?<TR%8Qpt%F0+kdLsia~(1A66GhNYu<BJph94%?a8sLXMn#nPrp`>kK<O|
;S$b~@`jpwzEA(Vey++-_svd&UY{|AR&gz34|cy|V~4<|Io)*%!$jRDzdtT;$BSlHAi$cr?f|Vin
`fsQCEu!WfKEj0#<tlQ9aU7|=2S9h=e)sp-T*R<oj+sP--~WRX#g>BLi(pphjcbkj#ya8?Q5o@a9
VPW2VZYe%gsB6FF|au&Qu)M5iy>gpBY2q*k3?1kfE{NCgj44UC6$2HL;lIjh!ak><fqn32Aqo=71
*kFx~s>~Q;wHU>?cKg^$!`{Zuy_Cz9<fwaEJ9jSvuDs1Xz$Lf72Bc?RPs|Y=-Ipd#los&p|0_c`p
QqCHZWQ{*gkokNL(FsQCK{nIUHo)imXRv}&zgg~#J2G`{_L`^sdm-y+_kI(CESsn&qcROUJmq{5|
_(3KVve5Za2#3m}ySJ*Dmu~3GMZP*IEZm8=wq@7Fmgjo-myH1rm2kgAUudOyPz>cJLl~(W{7zm~j
seDUd^kB9GpGd#sQdc1Zr-Z@+!Io6Z(jY4rZ(H{bM(u_C5<M#p_N7$nmM*Q&&oz8rSX;haNj$2bs
iFUn^%MX6e%sJbR!t+{JjFC?@d84UfUrbvUaiOrYMzMYxn#+b9aLy;DhEY1$4j~(qE(L7GDg)gO#
QH<Xt0v$g(v%{rO*o?SNFPWbRg-j6@8D0Q75*yjGlfV?iRHT>i+vO9~zuhQQ9rv#{Sx)wbv8kL;A
i8hlpGnkB&i5R(w=D{S+wZQ-3Zol*_nd4w{Xx8ZivRG9Ye^IxcA|q$)aM`HS;ubp`SE)*6V2I>wG
tB0o#?A|wI%2R>*bTSR24U^Myz7FN?@$SWiD)2H;k~PG2!3gLpGZo?ZfOY)5X!lP$*PUP9RU3FUX
M_4{JJEmX)L_Ss)=`s7#Tfkw(ikN0sCzh-UL5-eb6tp(JFPFi@$^Zm?8rzsCiW`V^$+!2|VOt=E+
E?MR_7X>N!t)e`}Gn5l~9BbIU0oheUW{ldU8UZ<6FdKm(Tss5G0uZs)7&|hNmH9pF6Wc_fNY71QR
7&TWXAKFbvrB^wMrujA8P_bzOCuRZGZ66B3nDt`eP-I^4*eZEvN-}~77bDV32MCk_l6XNr4$Mc47
BzhMF!4+$?+pIB13-h0cWJ2`<~|a&F}{P*@bc}#gc5@fEgy5(3op(V4Ihd!y@8|V9Tn*CFuX(wqJ
|P5)%#j~*_NPQ|H=|mir}$CwK|0%<FmsmdyWoLnc`$Ydy`k*6=5l|TtOS!NC86UTj3HfJi5qoQy8
14q8R@LU!M7BK+S{~LHwCjocp$L$hL^KQZd3uBC?W~h?Ni|<woZiWW;B>iUz!e*&hr;XmlezKOph
6d$lI-lp@9^m8b=E=cx?#5hk<j*dbdUMX|5B<~SXVTmW8!GR=`9JP`-U$|y$E6?&~35Rfem{kg>5
eYD+h9BW+f-K)~s8(w@njK4A{&|bz0B<pfryNJ0ZBY;S2HHf1fPx^tx40Wj^IpGP6-@QqCRwx>c=
=9hOo^v71=)4g!LPu`9)p5)?)Uol9OlY%Vr*XGs4EL*!Gj&<AwV6`yM+zm|Hx`4k4pgk}F|-9%Vf
ZR@-?xZUTL*0IX4kPV(fFm9-4TfSQI@TBQW#@>rxF=F8mWK>#D}n}YI9XickbQq4}Vhs^U+=bNgo
5&N(}lMx8koPXnc>jZ_{lV9Q^&^6rYcx=D1?rG~H?VcOZX<dKhgm7ogC>$;7rG+9V+uuPJqy5WlC
Qdbw!4zD&2}RDQHsqP-#UEyNi;{q`;VuFFN217uR(SO-@(0vTgxiFtR@AC30Um{T|z;%Cth@RyEN
$PS-qf;tQR{TOKP@4kZ{_(eoG)7wK$c&i_eINu|eh~eQMC75McyH*tBq`Bnz#l^O3{#3D>9DuXSe
gMRB0!x9(!YYc^K7nBr*{nm1Br}l|I-@OhmKlFMd<cBWekVGiVW2awqnUV#ocG_z-q^15i0kl}-A
YpD`>eS1Dgh4!r25GraYOiHD&C8p!d%{D%XcXzXLhQ6#nlGh*tps=fl2gxp!j}v)q^2d9R{nuxhi
WiZOA7hTsXVtqdlHrKUnh}uI+2GZ{-}KGd5Eq<1(k2M?8T2a5FSlob?+dGo6Zu>lXMe@D;dLI1H!
OS6qwCUGa!n6=l><0WzPV9ZY3cJltQm#&2e6kuIN=#YKL(T2hAl5%ZiDV;=AA9j;sL7w88pGaf~&
BCV=&l2h&&Lf?*iJ;5UT=%6jh-U!d|{wUi2O_6g`6+3l^3>F69RA%ZqV?3esF{!}??8=xT#vNj+0
IBP~4@py$Wlu0y0f{!ypRp5B?AI!6ISwS+dBoXk1Sfka>pQ;Ku_aP2sSEuv2{bs~EOp2cW}y@AE@
>n%z^)RE$-3Xj8>y6CG@4zLONSWDee}mu_1Du7rX_C{G+2ABcd1GBq!FD&t@<vH$+xE3ZFKP6chr
To>e#+41@5;D&Gwh%Jzp~_TjEdnQYWvebbugUc2bj|i($b&<C#fsNc)vnOgSknLKAds`qQFm;|3f
hE^Xp@OlY#}5}^g~R4BT?N)|D|!*S?o)rmw>(fs$%TJ}<}VA2qly?ptlf}Y)A-NS}}stNNQ=e#ER
&g5lkX}I5Lm@DZGMHz%4Ek1|f>vKu4IeL@!Mh2!TPM4S0N2Ev|Sr)cP)xaD2+&f-guFwbK4ZX2QW
X|$O?tVZWzL20bRw}fLgOpQ1DCQ$mX^RZ^@`7@jg*g#m4k(TeOW(-GSp{*h;9fOjST!DhFP%=usx
!^T;`YHMa*26x{|Dvck@y-E;H;e^LQ{RHQqok@*~pH+RW7yNq6BU&(Y#vuscje+MlM=ADBZUmcq@
vf%t$RtHcdA4)a^=Nuxm9pIOYj$*XQQu&wruNrxSq(5|@l?)B)}2CJD6JC`nY8Rn()Jn_4IK&uX3
-7<=q!$_bPdz~Ax+W!V41++J%FT*{zyxFy7|`Lt5`X0+&mH9de{<7KwUQo*8|hCIvXIjwkox5$oi
%J;6~x#$JKECLb@?iHVzjqMg?S4U!6zuMDM!gMe0BpTJGwlVYk7R#&#57!E21w)C<CoK&sdArkmX
^%BuW|JDT4__D)UxamllNALUk~Z<EaOP)hn*Lzp6`?Y%S3zf0!eLd<Kss)$dc^uheSA34qlz|-Wk
k<z<>8?R#JX4o>_k1Z9GPwN?vXF(Wg~GB)lo)nimew;Pw4_cl-TR_<kX$Q1*a5)X=S%$%IqjlHc>
}TK2$Tz*ahf0U5GLtBa~r3|6G;gW|!KH!9|ze@k_EMLwm{VjCQscJzoNh=CuSfV1rVgE4B#q2o+n
q4*Zx>K4EqdPa=X)M}YxoUFjPIl_h{1<M%+?U@F#(p@$|h_(~^Kl)qn`?tI}>fFH6utA(Om&L_a@
a`lEq8y1!T1~`*Y@I3Sa1Xz!uXcBtO%c5j2UN@xfhtu(WS$-g2W&~F2E`^Rqj)2f!In}mLDodMDb
iWc|7j<i7d2R?n8j>RZft|vOdj%(4#WZxpd*(dg6)dTKt5^*skb{a#w2ZM4s6oAWCGJS<ssVJeiK
(n@*Ej$lr_}A$)wLugXl)ZiI6aW0vnH-{ueJP}m5Ht?RzOx{XN(-PDmeIUvyCnGDHtDEZ^$P_`)x
N`RcXwuXvzf}PI$2)1MuG-_{@uE>;(Q}P%Dxo(AvhR#OtRh(XgwQimgE97kDX|dJvLuhpWtl_(r5
VYHh&|tVu&T84ZSKqxN+(hcQx;XD@}fr7_!YA_iw9>ftx!WTmn<^9j2Tt3pQ|xf?ljp7>rpT_?UL
Sv8aG6zhH6;l&vNzPPWV$15dVOCs<jX_+2Brl4y_5wg-_{LJ?Pei{ROYL5AZ;RDDI8!s`^f$NZvh
E5+T3)kxOloVMKowKJx{lFV+92r-9BcF9-QGjbS8HJ}62Pmby;N$Yc5n4Ivkt-($%j+%8XJ~I`J%
VFC7R;`*8{pl60sY(ylAaQw?7ct-&T&P^$azlW&{RzVCvg7DSS1dtKI9aXNZaaFzPkgD$H)iPZNH
J^LK8Ef-I{sHTSFf-Kt~~R<wvaenhp;-$B>~R^<o%F+@qY{q%#y3a~06Uy*SP(CV&ne$m#vqIMQw
`;8>+N17Hd4yn7}i8h%SUeoLw+;uyuQGoK()C2`Ft_W?Bfwejd;>b+9C*9+}{pmTYEv10FzX6gKV
no3rlh;lBeD0UpWX8%mC`hj=owbkDwt+UILn>;V4^w%VGXpfq&LM#Q12$=u}R%`p9N{S>Wj*8aE2
^sz5$a)=U)XOBKyeq{HQRq25d?A`n&WxK+Wc_eeb3_ZOD8r{kaE;V`N$8|<;tRUwrHn-s?PwO2EV
Si1X(Vjm+z!e1F}6M}(x4@iv!e|*=BmuAL%t%e1uDXF$XV1+CSV*IB*n)~fwu)`w=1Hb&db|q@1X
A{B(i<y{05cB3*yR-BuW<pag6$m&8lNfT%>jAd%=yhjg^%jAt#pC86(@WMK+hs&vn@>8%W`(s&g8
tAPLn->DWTPY}_PjC|OhaM7!dmuva_dhHIejb!hq45Lc=bnY8b-x$Opx+G#!IsU6Pz6r2VcYL8{@
_)Gf=2K>f+gk_rhgoO!iU;D_mXy}u+@^|dd2GqSqGqk2dm3c`l_`P&Y@;%wUxhs<GVq1~`6=;7n$
&bmHBr%6eXlq~0o$H)XI)C0q_XgKl&QDg?J_mN9YgwyLb(!;Xj0D~1ws)oT@i6ANAX1AB2v9aW@`
Ee`$AetA3iwG(Sez2I<Tq!KHoDkRh$stlC(#@oaL6$#)1f)*n|$KCJX#(Zl%Uq^l;f+>lp0yD!#u
y;vLZ#8;%`~g^%Ti^uGwmxh!d;x#ue*1x%-BHPL4m@piVoycl;LF^IJ#KYPi4G<dY}KM&K!?M9I>
*wBGZZdsV8aJLsd9Q%Kj^Hej`^`{)Lrr1J$Zh=oXT(uQLz!Mku_zp}R_hZ68yG8<6`erwPtO{T%}
L3hj?P0~FQ%U0=KfHvXe)Rz49a+R@r{10#Nf`9i$D0e?$(p5_0<s(cOK3}i^;E{GKrMW8Ze<66wd
($M@#IlwC2xE_T%KD^lp@XjTowM;RtIt#p8&VZjBeKer9z`*bQ+~LjZJAicg)xSXB>|0!v_xT#lv
ycC>@FxhJH@6_v8zmb+!Y(0-juLH?=hmmyQ_Q&C%sYu#Zc{QX|+nvRo2Q{)yS9>8D1-~J~wa(*0;
T$4D%miSh%y#*%lc$EAg>rJSa_ruAPvJf!l<6OUTCVx*_x;?)S*fWnmP-9Lz&?94diZj%92|vS2|
;3^WpmYArHW3geLj=D`YvOUB|B&m1buY&1vXoVFDrFI6ZK=I4S{%y@(OU3gJ?Evuq~<oNVmxU>$Q
)4+ql@=T?U@m4~Ac&na{uM+M@$EeYDbm+?^sW~b9PRn{Q;-dho{4rR}ZQgR843<Wr8WwIb7dYJ^P
4=4i^Ln=Sy{3_ZWqu3D5Sk9%hI=GYV3<r$5)~w`TIj-H4lFGv?J#nn3_!O2zG-v!)_B<Sovg6&U0
3HEQTawVKYJ*@i2YCdDj!*cprvgqzfdVHW5Q+1W0O-6p<EG~Nqn}`(BN$sq3!@FXEv;bwa_WCWN$
jrYB9z{K1ZiJWW%7wf22Mn8=HmM#cdm*TQNOurMywga-=@A41<yLi9q+6TnN1DvUVFP(%z_wR7s6
FT+s-vo6y_B_DMXjqsBp2p^iDG0m`&i1=-LAL6&kwa7%U|i#BbV5#)!DS-aSddkKl=Y`OSIg|fI`
wR>#Xm$K!`fQs;QMZZcmr6BPtmjl@??<C<xvCl<=qfRy`;Yh-tS6*^ss5)9Zujbr3dUEaDeOTEzY
ncPH@!L#bqz8}Kt3zZdbNCY2=~JfCB27rzq{M`)i*ig_osf7KsYgt5XB0MD<-A*?&lQ2R)#^Galj
QG1T?MIut!iGrK&@S~ZxBuiw?_P;Q3+qcj7zAg2Y`xfG`>cJMk=v(wt0=bNd<EDM}eXnC1T#JB^E
7>64Z>=O8Y1or%=m1z#SC|=VQHA8zg>4lE3ZZueVHXwV<;tR%K$6DtvwA&#|G~ZtCyc*sbOCS{%U
)tce6n9OR@d82Mq0hg_w0U1pc*5`$D!Ekw?OxORmg(A9Unz#K}f*{}ZuJh-q>T>b}-vnQX>BF!*4
*G!b$D#Rp8(a!_BBKs+ejx;o6vjyX-O{L8WcT~40DhbJ%{YcU)IL}npgtOLu(3Q^g1K<8#{h<Gt)
lq)&**nrO;s}m^ZL=0%FtgWA-*;N=%rDbsO?tSoCQiFi6CZA>sWWN>)~BtG$)pijz}8wOcgX3^^P
k>7WD%fgp^+y@$pfMApw)WXk{Ot$RDPWH!AMl3QRrZ*kVzqa{<naQn=)Yuu?ULVv&r1i)}%HIlug
pLw7A2NViaKW-$#WviNAZ%-&9s_Cz%iB%HcFSlCdhU$pm<gk>c?Z!Wg8>RiimSdk^L9Ve@S(Zx4Q
>ga<ki3I~esg=BW&SYV;;mDf6@YEz|u$I??P0gIbMNaE?60Bh&vwMvo>8x)Y=R+8iHYbzqHG+Y*>
Ye;Jy4F9r>R)tDC*Q&cv0r@2X-4|6O?;M&3*vbvRDV2bZBFgom7pXKX>L)9qGbeuLjPa5(5~tJi!
;99-bZnV)`3Y;CyfXII_z}^Xxf7e0B)j5B?khp_h&oiLP;QxDe7fbTh-q5xTLnt@`@^Z&8PW==;Y
cvG5F^oU5^FAK>fFAdy=j^U<}OoD*4<?8^=x{P>-qEdf|s+^4PVZmshcely{+G37hFw3td=W7rOE
R4xU+!{Xo$|e%}q96&5iZhd@(l`@Ds1)*5rNLUdobWPPN0|L!<buNd>zbGulj%39@(VH4!^UF=zW
^yl*J}s>$_3LSekHFd`RX`l*DuyUK1Ol<PE6apuQDSGv_yabMg*f$l6+Jg;?<&R)P3wes#P9dIR>
0KB@&vbqh?eoB~_PYoC2ajjD9_aa%H;{nmBCY5RYZDhZWyVgX|BtX`o*h20vv})?S2jtBNL1R6(`
;}UTUVU4)@Plp`sOF$_lSyYCJuXt`u(nMFl4_xToY?U}_2ojTp>Y0Twa=|4>uI#@YB!&DcC&PZRb
f1SN_G*R{;xVw)Tog;s%^zkb}5mBMy<J;+AG7^<^ipZuCqb@B(ZmN%pLFCoc-1=k~0yeXmQS(nzr
WoR5tRvM|Kn~AK!^pvUc*KuT5m@7%<<D9`^f$>en+VQ}L?q^>i#R)rRNzNJ{JJ7{2g9P{maAKgsj
yf~<1r%t+s^K6jh~>;^!4*YLb!DRJ0w;LK@899>6hT=G(7QVFUag$y(~N`I-!A`rbuY2Q9Eei63T
o37@ISohG8QXN8yMSV2TtK9I(Q4iD}8EZ0aogLfz)sa~yUj0b>t9UluYL#IbnsuO8@e(1eZ-+pI<
YSX^kt4$h4^U&LoSW`XH5*lRJRf|TgcBu?htCS-4maE}N;)mjsXFdSNlf@=F<Kin-F|5BQ#kTDT2
5#;2O#Z9YCferhWL>tC{gCPj0$L#o@W&N1}<bVBylsvE2kVk5xlk$NKAk})tEKX`GU=L<AK+%?pQ
Z`Vl{fk3Fgu0DruSa4{romV$04gq1}0>U$F_BzE>Lp2-unVg3WQ%fRd;Sqqde`=^<O!KW7tE+TxK
$E~;A6<{+Z7FcrFolhL4m*6QiQZek5nqNXxbFr*$p^duVe*E9<#k!U_T2q-I5=gqXxg%%PwptzVw
P+oWCrX|+6+Cl5c9mr@azdWNkcEY;=X@R*UKU7w7NY-=1RRIH8EmQ(j^ub={6kmGIGMSzVt_-IHW
1Y^*^K@3liNNxBOmD_xJsPwauP_QlTA<?{zU{z9PaJ<zdVC^rD9!@z)QE1JP@a7@U8aR2reu#}l)
%$55ijF01O9l70Y-2@(qDB~p;obuDewqx1)%30%yY81gR6jpgzaGF5|ds57|c$zAiWu9_?hMB^9r
>hUsMrPo%SY(%}IoF&iMdk<FHIcA+d4gkLlqt>TBPiwI9a&(YbG;p1dydIR%!IO;M>RtdMg#w09W
&C4U-GehR>N+Ig&q21CyJ!}gvWhYb#Jl_9I5=L54%P>_|gPW-e0*s8BCRx_HX2pVCvrz?uVU}pT_
HY@TJ=Zg2{<!Y8vhC-57LfaWIN|-!qd7aMa8KBELl{nrQUXF%+L(vClU7qH(L^g$4Lm7#GT-8fNM
ra|4wm7i5g9D1Q=Z1f~p?e!n8!~8BehB~o7`&)49vu7JF&8!$rvpq^hHFKAm{CY*xYOdBx5q!c7{
7b@_ZI+#d&5Tuho{94FJFy+IDY@^I}EXPTD<!4hw-!Tj^Dn+uMZFS!JD@)e>i^o^Z5H0ufBc%-8)
XkhcDi}c=r0$bNAJ7|EtpizP>+x`aN`Z{LPE^Kf~jL{nO&RAHVqqI{WGA%lBAv0L{O7`{MoE7ccP
XyPtn}`uclnqHkVMGg1M{|8V^BRpa?!NIk*;8jp{^fBEgJ7tfvNk7#GUfBoz)?|**tV*K*eU!l}<
_RBPn|N7$X)8qFqe~3u-ZJtYuyj<q-kFTD+{s9L4?j60O6Z_`%yO-}@zJ4`+_x)??Io|7Y5W+o-!
*&4wWB51t{t%uY!1u4<`v9Za4Zp$|NH2bR|Mqw+!;bC1h6DN;($60K?9<Of`Z=JVNAyD>`1}j)s}
BAQ`ttuk{vXQ!d-DIj{Qpq?KfwR3K!@Y=RX&@J7iE>>IT|Cq6D!=OLStbzoiA}hR!l4t;CaAvb#Q
)mjn=hzo4DB{@Wtas)H9Ne7%yL~osi;t2QB64{euV5(CsK-{G@6O9(nQ0PVzG)P&mQn&M+AGAbR|
mtGHO5c`hYyaNy(V@jE<{;pODAlNn}JR@tgzEgLj3rK-v<iD4F<5R*T=d)no=(h~Fqt*Y1J9Y9Nb
Q(RC8=G^35H{t)s<Gjf0@i@j1Qf}5sc7~W;^zvds3=`#(cVEF&-JPSSFru-fnhw6K#uR|ma-_zgp
!W%d5~Q(sany8gkJ&e0kIR=8os+Y-dV8Yk`Qj<nTvIcqax2?D$?xg5f%#+@Q!dBYh#03wE<$$6xG
AHL*|HS>8_`L@hV;Vo==$?O7u{ha0b35#g9aL+K`3(%?TDxslfa(1(^6!Kz1ox-hoiFj%YEKgYiP
E_&fPRv`&tK}qjPkaME`;Y*8xcEKl)chb{tqe-lNlffLVte;7JlUTSP06?eaZkCY}`)x`Hvh7g*4
qJ12qm+IY<6MgbVImNBt=S!CIVwmy)uriicsX@=P<?}@)iPoBu)aP#ig&H*>H^&U8(W<*bru3(zA
u`Q2f8Ma*b?hzOFfo|=%WOLM<)Vpg1akQ-dTiFPjwEs?4@45l{S1_sSZZ4y_Y8#17^4MM8q0`4zk
FO3hw5uKu;LJVrQ2GfLFW^%n5Ww^nuO<WSstr$!OMr>qpdr;GwDIIgn-x3t5Eh&Tkqj=)9Ig?#0p
W^)cX-pFsyt*3jJFRCANpxP%%8Dqu?+7AhDL`U)&{0NAUu)R;R)dCA-a?WPyQ`4arZPo3l4>b+p?
1_c62s)UiDxaCs6mS38V1TfztFQd>h&b!NI_Wc=(RzJ!-w@Y4~l2a7Ho6nCy$GB#=cON8lenmspI
Mh!S+M%iSRn=~v?yM_j;v$2d}95%+Y?7d3iAkavr{YD9rGmW=5h3{ErVBywZXfdNrP5KKH?kDD{f
vl)fPW+s<Rj3Zz{X8=uE)<|uyW@4sgy_1=kX<6wFs1NmWX1naEH8l%t5!pWB#nSyb=Fk#s;&p`QQ
eInS;Tmyl1IhRXN*1fRL*w%l(0^^z)aT)$(1mI4N!UJuCrj{;+3KaEPgc&&vh)HOfHL5UFVv5kZE
zS^=83fmZRms#n!s2{MKU(iRvjj-zCwsqaO4!p_pZfilcv@rO7-RmmUsE8l1Pcx`8cWOyx3Lt&Ot
jJs}+AHa@XPB9SH$oH%F)l-kz5;b)e}|@PI8rYKmSmmEpg(n<RSwF%xhBIQL&!5KaeR@Ngq!Yq0J
_j&S3D6F^t6dh|zu)tnew<%2LdV}N`YqH(dh&1<4DTWI}>rSe;6dcS_4#IBPa){%W=TDz9A3Lw|?
n@SF01)~TcYrP9ngo3T7wcXUrIZEwQw4o>tWc%U@$5@kXuVSxAyN7^)kKKOz^5LNuK#K<t0eldwh
+P}3S-%#<_o)!Jehaoh!fWr3b~G&gHc)YcHi4&i=h>JDm<F8^qHR2b7N)U@%1N3b#V`fv4DPl*o#
z=x%V4_VWMt7MXW^JB9{GHpP9sf16aC@S&CY<;1*53Y=R|5PM{A``9T9Yo5yx~S{Q8*jr_VIQ^Z}
qAAK6v#>u|71Zn6SyZXr4nt{hQniH7h*C^eM6`OYNtUV4_C7Ie*6g9#RPvJ3c)w6qU!R0L#aq)=J
=GVokdB{W}X($iUVpK;N`prw}kEQgVEQ0XD-a>k?(X#g*;Ed|X0PDsLq2V{d(LXRu_8bgKS7WoQ*
hSajgyuPTV;?3#@3y^1G);46g|Hiz22o<hA;KYW)E<h$B#XVmd2bclVXC5i0EN-eyI#EMg;=={5n
b(d{_3WYu9@wixU}zfpl_a?9<3M9gZ4ePgzGlX6FrDR>1+AcJ493yW+c*-cF~%2C@=wys!_mL(MA
zPlzg0LNOC*~PIbs{dPhsQ|m2IL5ATMn2<Q8v%>jo0P#d)jY{!di@=976=UzJm92BbM0tFh7OKmN
x?f6YO~Xa?Qrqth$uOngz#HQlU_wh)V9tFkL(&figbO2FujtR3%{TSF`k`$<SVD$q~&53ROFvK$6
+KM7xOs$Te_3tm)GrLoJZQ+0w!yn%r}$y<T#PvF(*4l^YF8F5+iTZ-hpv<+@qFn5cJ30NX;q#qko
b_9=Vo=w}gj}&$IQQ(%o3$3EbqqK%ay=x<yZdH@|Txyv1Gr5pvjt6(R-QXVL;D-JG^yt3YZghi|r
TaMiT|4IptAjXVnEYE-;yT$X1jPEW1%|evOM^W`u0}+NAP~v)q=`DBcN$VT40838$_~dSBO{$=6c
?XtEhIxH_kvN+*vN;C+NXppdp14()2pWvJ&2@toR=0gqGIEr^0ttL3i~)wY%27B!rZ1#P+~m_PV&
wMEErTgUEXyB0T`2wju@w4st+8RkPm5LMVi7A-`SLPrKJFX(0?e4^4pXgrvS+b8U2n&P-WSNKsYW
klOh6;$4~xDx9Oyw-AO1fvL9=REgM9yY+BMrE7~OGuD!Ei0kttxlHBMvEHnT}N;3GAu5y=+b`2$M
tghs(PD4kj!<@Gmv%wT-)w<~sI#MW?<o5}9znojd4n#d2D+)bsEFuq$Qk+{xKD#!Njink=-|P@|E
zY`_`tB@@Vv~pQ*bFHgn%bx8M_~<41EDsH{o)SV(d_)GT`?7E{h-C*{g*AvhFOC+CwayJDxrR9sp
RrEzA%;0IB{pvq}hgMd^zht;q=J{%zoH)PT6Ct;ZR%?yVurM{IL?ejq7q+s#+FrxobDtZ7`-G#iZ
5Vli-G`c{iBAHT!?jWczHs&oSA;HH@1~<e!^@+{Vr_$S8GN3xG8lP!HVpl79;nA8sCx#?1`Ihb>U
Nh7WHv=7Y<cEy0{b4ePp2)HKA~5X@!mR!g&+VmQO4_rcInhshSvS!@=T*pv@v+wW}%W2&~otjktv
Yh-5>R~?qSh3!y?c~k5RXH<T8@Ox@fu3=lg;0r_6N8#3Mp?R+D79+S2*v1yCpdiR*^G^D=FAmSvT
`_9~LhD0sHx^G$4ljIAp0a5xY__v0EKb^De18g_+=L51Z4GqKcv39GzAYD=s)?b^U?ZUVorFk=V1
=M9V#8=dlTlS1x)ppTZ7@tWo~%BFk*|9kD4bJ`uP#pdlqwwnhKx41INO78JNu)<PitowZs!mKvv1
MRhG_D^)5~`L2$NRsB1a_y%*hz#T}Q#oDI8`&)p=sk9c_Ad)4nMiFk>?GOZP}uY9R&v3)HExiS+q
Am!^Gtw~yA)XQup<wP%z3Q8G4f-5>!`n07r<b{c$aE|rbJ*^t~k@kvj-o9!02Kr*&QWpfNPXHz$n
ZP(ieR}&i4vtL)Go?ID{&S~M#QNWvH!|L0u9fj(THj*}tyNT|j-$U5QKt$hMWEpyNQ4~1TM&wmQE
w9C7jWya`52e<)lPy;rTGU=OZG<p^*Nn1jI$QMQiLC(&Ehbgkd_nSvwC+wWl=eDI21w(BZEoM?pw
m$C_0^-nzj1WKtwuLoGrHmD9$mF5aG!A@(VK|2(g&<GFn&HK`08xK@Q_t=d`Gwzu-d~m<LWl^7aA
6h#0U}o7!Tz(9PN#^ij&N9!r+Lp$2xIC-Doc%?P&5T6LcD0cgTfV`lQAQBzbgOFbHdg!c+XDz709
H)oJt9@BM9x<FT24(m9#0Lw4#OaIRAqZ$7a_rJu^`QA<c$vtN@4Q_&l;g>cmVCK$2oXoHZ-7s%M-
-r@q4C3@26W%K13YJk7}o(q&$Nm@J4?l7ntt0p#Hn!o62OZDz2teH&amrvT`t!E&z@=Y_SmXqkn5
yyAi<Xp~}A4mB%NDm3LUpALxdis|Qbaa50ML<2%6F7m{oNZU1Abd0FYA@6FrGMFi&^3#{0rT+M<X
f)IA6b`ASd;D7Bj2zVThIx-Of<T#bKL%av2g3Gel5OgJM0_c-rSlSIsP?bgwG;2V_oaEmrrOy>v?
xipsflgYok~*Fwn?$BVU@mLCayST|cyDt?>W*gg>?{=W#3O6G3nkb=R*I>Ugo>lc0>|Q{+~1MWL%
$DoMav@1{0+5Y`SPDrkT}x1oFkVsx#(uQ6P<iBNZ`ZP*Y|w%;nS_$`9lF#6dnt8HoS&(YxF+V(6@
)ll8WurC%(ZKYR&!W8QD3lGy3a%;xPQwzJQS*0|mup1l>rwT>fF<SYP(M4sU=ZnP%hQABd&cYdjv
jPR~7i3EsIDFIanVhVaY!%=rdmD(v=(+<_4TLhJ`)CUDm65f%I$~@~p6#^d@>!RK5tB2~I^VuHTy
sKYj_dED_0qWXyuyn(AONS|Y7V0*nuDDswlusGRm5GYEcPuE>B=Y{AL-5>>vdo24}<<vs!CT)7LE
Dk*%Jgrk~63$yHWerc|fS9M7QCrSC=yH{ZE}D?c;un2b12QhiwK55*ENZ8e18xIh8{v$*qDH*PH|
4@jN?F%9{|pI}u}=kus{;jYza?dOH~vXN_uOnPd^LbXC?ojkm_|s7vnxb#2p&cI;)Lq2@^l-7QB)
8<@5A9tU=_w&TH8t@@q{Ew)$z$xD-xpptYc)TP{S&V3xT-r@i^#;A-fovK*Jq%w0j>fa9f@Go)Vt
+3ghZ<<(*qS&)*Bu|ngTBP}sGDZKt-92e@+c>g+g_Wtil{OMb)a7H=Tbs#vX0w|(c{%oYj*6ir+U
A53HKG(-N#(z9pCCX|Hf_)QvQtyBNCFL@(cNe?8r^c4*!Hy3blMET>Unvri%bfc0j{$(XK~xiTO`
5h9I``=QcyW6-c~<4autN);xyPgqco59Xz4_hHRu*aeCu!<Z96t*;ZD{rqW+k1yKR?z^qw4PH+;t
@)T!-8*137+T6|5&xujB_zkO@^(6`&N5&VzWa!m$~Lr`S~tlL4F^gZ&Hm}7{-j$LJDW~B3qY3DN2
4n(`Rn{4Mu%h}X+la!MDRieSIl8caIoZ2zr-Xs@n&76`>!vWqnJR&TN8GD>YY34mU_VQ108n3ejs
WCsl_M+9C!@#}SEMVnXP;mVp)0lEdw?2M6lb_u#`kh{^(DfA_mfQ7ZMltwIf8Z^~8T|OM?Q>8$42
y$7`if|ACb59_22?(f7+!vvEG4{JaL_%&d<D>Qvg`#PKYm!i4^h>yz+g`c5N&<@$WHm)WxT>zi!>
hZb%yzl$@w*(u9D?ig7VBiEGYCfJTCx(K^j7#xT3JjM16Ye9rLFyhrW9bWBdUF56<J&g(P84DBSW
zoXz7k`U0P$Cv8H43O`e?I~a>|L9a0aEAj|t%fPs)7^&$K$AIHhz8LGyCv@Xm&p$uArmu*rKd?)*
|LdHi{ByKVnzs{4>&tl;FnD6*{kDOfKE~4XUM8Fdc}Y3gfaGG16No{^F{^NqPnf3y7*OJXL*dUDX
LYS9CC;+hmP5XBWI#$qNwXS#iWdx)!j5Zv*gxbjcTh<qzG7$voH>{jB>Z?GA@E4NgL;E!Xc~<?(O
Bdk7Vq;SeVC!fv)we<?Q(ksM|8VLhPb)Q*BA}`GKtR(BQVNszv$C$7j%pdkKiAoCMht%4>*GW>>{
4g<09+AH0e*69sY^y^vTng#}hk(Uoxivh7^`pA7HzAX&x}7f&AoramC{{w;-G?w;vXSZmf<4b5B0
~?*_AMEGR7GKjP^+qm3vBv0^sDn2H;~+lpf{5+iOF7~u$Z9zFia`M8j*W3ScodxPF^-<y+@JjSg4
4ufz;Uf}N!;O%*Gu^}&eB8;(u02)X+>M%Z07E_ojyc5%dS^ewN7q7ziC(qx#4PPI>318w3I6PtNL
2KUk-oS?zx#$0+t2$>SHDGPXR!qAc<WUt<Bo8PdocA81P@YR7Y)oHG-tx$V(CSaeKfikOGW_w?$u
R}x(<PrIjkk=`&q>Z%6!}fQOcrtFMPR>K#AqNWo;g!t$Az4F(=_^=Oj8F~>TQ-Fw1C9ix6u2z@)F
su0(VslcU22_RR?!f4>v{0d2#9XU>c?8<&I*iiAtX;byt<TtD>$f`%I!I|2o#?OWBieRO|&F2Dx6
d<n8x*`(8XtfV}^Jd>&6X94|%k93Z$BlHJ?CAHO($_v$1>z!LU_6_Z(8GRsKf7p?<RlBCjg#{*IK
r2~Rg`Kfq!)jpK8I~aBpAZ{rzEwKwLfpmf7J773Wf0*T{ctqa2F8#c^#D7t)@J&Bl5z-7K^tJE(j
9ii@MZRCZ7wnIKaH0F*-(EdGd1sMrt3Mibun7EzfA>bCe#h(Li~T+OgZnq2zp%;mzEg$2)q5bEz=
3nn3-IrFxOcF-dL5X40jB#9ID^_@?T_~FI4s%lwgS7@{%}wF7mSC^;EZ&_Z1fEF4g}4?py9a2b#O
)j#v-M0jYrMk$X(FZz`^r9I<#L4=pH>fsKqoPm^-xJkPwxk$Bd#8QBDvXj2O^hzu}YxO42fbJ*sy
wK9C;u`awfLeYZ!9+Wt@h^+!#4Y~c1tzV~}V)q_#LAs{7dsrUdSjfyUHABLrIsZaMu(_R%#KuQNa
1r#*xk`i~IgW(dv;2;pH>^H@eA#a+Zpg-yfo)qJaC8W|fk0R&|7%i|$*aY7IkkWU+too2XDTN1I^
8uY2)T6vN?ulgT?~NORQX=m&Asr0IJiL(%uYb^R^7<neQtx1&A?+DR4N0><b|5_j<x1pz#>+#7w_
gJFfbku;pdK*5LC@$ov@{*4WEliX2n}g!5V(-`f<1w>Cy@3B4I%X%NW<a2AS&3`J~b3A1Eupm*L=
wEh9yuB7~jYR^^gH7r4Oj>(P)nZ-@#zOYg905+NZq|paZ6;!BA9=ps8#b?3W<*2Mj3?(K2kh!VC^
vNVFaRr2bgYv^Qv~U-n!`{XQXlZ*P2XM}!Z9GM)(1{-}4?sT=kkNL3;T_8RILL#1-j2JcS=!(kcH
y~$uWDucQ=9Sp}MP!Ax4y%MMgP{Mu%SNA4`0~gc-Xklb1oiH-)4TBOXG{n@%5c)m?;=P<j3FC%K%
*YV>0YmEbN`x?Oh^LVf`j85Y_IT~J=wR3sk`nrm**F+7$Mku5?+yA5IcB6}K4eYm0SH$rAC3gl{V
}doJ{$|E`=eZ`e8{WZLvXHCKH_ct{gFOaA|J8cV!(^|-ElrPo6kNQKn4f*MEO{WoJH+;FdW?z<72
b^95TCz2);YQ$4caEz8Ve3EP;C>Oh!S&&HmVIKZTy|k8maO5tGwHFmCpr`_ifVqg;u6bRhh4f1E3
kkA=wZjr6^qG1*eyj_Wv#Fc&XH?vLj2(T7K9YgOxQk>i@rL4L%W&0^8*l110Ei+4DOcZTPM*}_g&
b)II~%4?BTwC$X)i+{-3a_i$yU%Qk0i}=dUql#xhR=Mo#*BBFpYAH#8BIis{3Z07L>$RUx<3$WlX
&O_;DN{2|7N1%GwWiMJB)$qMySXVHLFLcrgatK<3fVH35<c3LG15{Ce*hkje|rAT95^FR#J`2mcG
{oNF$d!?S$KtsSi3_<CPflnEBS7Xog04r20wqp-&bunF|P&M&J==&E}R&~M_YVI4H7y(JOaA#Ocr
u#we8lVkSb`*#x9^IWQMkRI|`L1MkXuzDwBjOWL-~kO;9Q)v6y`_S#K#j9KKjbNlJ&Exed>pP;x4
r=_S)*q^FH&dSByVsgNGw)-Uy&Kp$CSc;dB+Q@2*@w<{Z)?REoC{J+RiT?^0Ji0ydu-fowWX0oQ@
LwonMhVT$V`ytF`h@A<sH{oye*lc!_bFYW)Yz$H|?@%8qNq6w&DRp7uOYtLl%a4;ADr|C0OS@PA0
^Bg1*0|(|=JrktO*swFft)EpbH3sn2V9Kaa4~9=o;zNKNd<Sdx!VgFt6?65qa*J9q!Qy$yKq>}p<
8xgJdaiYE$3^d*DbBr@jk`dqcobI&CodoNEF?YNDOod18v{&9FeA52Ao?8{eD5dk8YY(p?QVSNP4
~c@o&e^3i*|07cF;bIK*U>e5hAs>rF0LI5VZW&Nd`Bb>WFt7rBWk0uL12ZVL<oKTq|CPyL5>yIo9
c`@{<lCx{DvK>?DbB)eFusFd`LnEba$#rxrraVX%UOzaQ5KY^}x$XmdEqJ)u$T<Rj8)#Rjy8fTQ`
8T~G?%CFpxKH{3B5GC<14X1F_lZzwtk{J|-;$$?!Osq$QpVJz0yplw%gdrJdhp<Cq<DWP#{zYTrp
WL~!C}6yuBG}XZ;bh`8O@Yiy9)|q>$m^HVzj42hxG8e6Fj+E7Z3z}9)fm1`1HsJ=FzR<SKp*eaK*
gK2TudW|QxgSIBa^_Ih5jxkHJl_-J%t&WXl7U~Q`DsVmLX{>hAWgoujYJf7W1NKt1U7qu5x(`WiM
U2SJz*|T(ruBxL#6{_l|cJfnGDCi!%8UQlzWaJ*5g>Oba#(1oW7TjQbaQUh~pC-K=PdV6CdgQ4$-
(q{jGLv#rM0Nlx(z-MHX_MrB*_HZl5Lnw+g7^ak+J^-#uvD%%mwBW1akoZKea^r4+=0^g|ihU*1+
_23dgKTPUwEh3$WW;0H;Y^hybf<2ijppgyQU38tIIWhmO3kA}%H9zE2Wx?_3dK01(+O`Yc3b?rzY
&B;sJA@0>S*k^3`lwVveB`E7Y$~J~otheS-iAkCuXh2RzIpld-TODk6=s*NShbuk;xwqAO83G48K
1jc$822Y*pZDgKj+~rS-EV+3bCwC?1IAHCZ3g(9o`iA>#Od_#9pP;@us;O637d8-olZ*%r7#}g@T
<D*;NefW<I7|^~|)eh~6breKGnY&RS3W&&7<=yjhf)w8&dt^qq4@o0aj@Nu9tGaOCDpr<d3>fcW*
B<sE(YYq==Aa$MO3!|d6~MQEyX0Y~UR`}KCc5%W~-o?!q1>%lUOrZKeeJ&p^C=JB$WU%WKa2(_9P
2hgbe-QvM@sQtF1_C3Z(xTx+GQ^PKrml5oU)q~b{!PM;J*g%_;x8F1??UJfU^$L-~&XFOE+#%RAb
SLC%QR`OOE?^RqpJZMHC_qGG9y#2EB0&?#LvNjhm(Z<{T){w3U-FK0$<Au*Q;XYDg{G`84!zNJOy
P{TCSY&G07Tb>X}^NKFL_SS{mQxyeGR!MEnH=Ba7WBDn`MZ-2449$;s^$M6|H90JLLq>98eyd+Cs
HP$d=JlUaMqzVU!A2ftqs3CWu>rb0>C6?U%=I{|XwIO;J2(kb;k45q}Jm<<gGQF8VDm_yWS3Tvr|
a8zl>~2azbuuC*1xN#YUX`(%m{dTCEezS0XB95E&dJbVVMx^&2e3PQxjLVnreKONF0tm_LT0_am!
(cxuC3SuX<6MuH1{*-oRK!S+WC{0@tE!{u>KOMh4eqry=cC4+Ho`@_nvn0TggG%?unwrD73D`658
~{y`1-YQBMr{~s1g&dUZIIvl3l7gr8yovQjk5C5%rBNH=GT!1w#K6xW_TGV7nkdj_H19+K!^Hmce
50KQeF(neOjGDe<-dOpo;hf3zN^a34;EdAf2N`>V9De=%Z>^#E-exz2>i9;H&Sw%?jCtqKv#^$!s
ik!nW7_v)B5<cEdJ#=7JVHjZ%zNnpwW&e06r6Wiz#<k^R=UM=e*5ELsAMZ<Sn!us2I_o_2lmpNqN
AWRRG%46`c~D%>2`CtB=V$jR|FP>c^_C?2luhb^-?zfcx1GGOBJDS@u=sS2tqG2Q_6E^V9bQf;<e
Uk1UHA;z8?%VYj%0xqUuoB%YXIwa=((W`T^Z+qWU16-)%1#wp|bkCDncuirBu)}D?qQ>oppK#~uz
9Hbg-zz|E3sAugpn_XK6_e2^5b-5hww!tCXkBYE%$#CJ1fx9+v_%7L1A+*19kHHaPx#xm__o7(Tg
;D6g{fkZq`z6tq9Wdc=t4PO6k0RKJobZgn{DXQM2jc%u|GJktZNp9^O;4HIqyi%+P~ixrb|~UIJ$
;x+hA>iW#9rM;pHvezLl?4()|r{U4z648Y4Sou_wc{)@0{;XX~QS(J=R|pbi3O)wC>#?w*ir_PTk
u?}Aja*Kj+hrox1hnybk_Of$eI5Y}?r0x4*Y1)TTpwn;%Aq7E2&v*er-%A>-E@Mo4)bd$$oNI5gh
{oRK8dym27bYPIhaz|XClMcHJyaP0inK?S1HL+@^rHc+nd_2QuXkiTw)R_N<7DFuLn>QO+5NEd1B
L)A2qU)flBh{M1g;-djW(iA2EhwG>{86ek%hoOG2Z|!oW(gmrPD{>#czA!5cG^YbiZA3DS1Zto#B
KX|x`8cjoFDZ|TqAh(u87I;fGWC(l109D?ipqts5NOS<{#LSsh))Q42^2=BT^9bcWpsCkMIVWEYx
^gFpax-4Rodu=NYsWm9&(O9!&Cq9FT49DG8u#qm(MMg5xo73sVZ-GF@X*3A_e4OQw7=hruo6QsOG
R%K3KS1*mYmC(4m^x!bw0$ZE5wQ7SA!u|q6LW0U~q$V;KyEiEM9@TTjMM9qS-(%7PxSC){Am;>Y^
(&QZrAvN$#aetd)Q(o{2<5r>5m=*8PPL-R`nH$6ZOR?}-d0eJ+;SaXDv~6m+!a`QZCY&t$mD0MXW
A0SMxnk94!&bYr33JY}qGWYQ|H3leK0PcrVq%}-KBsLsP$-E8y5pCfV_Ne#!UR4nBWD?~c7%Obdd
WBQITAZiW?-G^>St6Bc?1F7KtvItXdo?V2rE1$F{iN>UyLo75NvhSzPrzj=<R)ZLSrm9PMgTU@42
#`ds8V~lJiW1WSgG&(QMW_mD%Ux9s}Te?htNy-yFYw@$}iT6&c7TGIN5fys}eI=aON<^I_F+wRQT
AG^d(T2CH8}feIX;^4j7j*coXbV6Tq$fFs+4TY@LMzDmzo?ILxB?FFcJ&G>+mcKbD274EHxciX?K
(gbRggs_kWA-*QV)UUu9JC+68Ud19#uFi`AskjV|L^H>Wv3S_C<vXxhmiqCvt3|2MD>Q@KREvo&d
$gVTYU&-b+90z{io<Q7L~TnG@lE;g=!fsV`_B98@zbA<-+1totup)lUXOp#=YJf(dHej;N%4Kp`g
ro{r{lN$sp{#XT`5lSYdU3b8Vvapn&bePhRI)i7V@f1N^v?p?gq7<2$s5KNe5IQj;i>>7(K<EQ`_
i4C{tT2Z6kn)AN%9;oBv@7ub%DGI4nD`n8QL~tB$9BB-nG@9n;^f{QXjr;5Za4M1QyP_lx|!GKOH
9@h8QU0~a5^dH(c;J9Tp$dJ?6fp;C;F?CWdM-Z==fdCTah*lqOu*m67C<$hz)2nBR@Xrv_UxJOtl
Z%<HGpB8Nuc1d@Beo)h*JEEQF01|)q{Fz0_cTpK=5iltGN{>vshy1Nzb9yW*7LGpiO-<E*d-;}*3
t9PEfQ%8DLpw8I{uQpL+(WT<(`9>e)N5Exy%+AbP%KcMr9=c=0C;0?J!rKH6^Dy7RhcFaRj_mffA
LxsUCUxs>6IyOcU%VLuF~bIGOpx{6RVL|a$AdQwRm=~#F%5z!6|>Ce<wFPp*dtB{SxgLIL(5C->o
Lvotwa}Vj4TU7MvdTtBz1Qo{~mm4fB*YXFMR#2`A;0cDPP!`8I3``#WHnGb-Bk>01DK8cghCF9Fu
$g#%q)<xRkEf;OtzMRf~SP^0?^G}synl!~HPk{Z3+B>K#e`gOvcXw_F^846_n0TNk=>)QO<nqOt1
US9orX36WBeGQA<-Yqo)Q!}`wree#es){suVNVp<`D;wR{^m2E0jTlcp*s3fB9RT{Q>J4Biv8v=C
V+EGmseqTCN`fDxwwJo0$hJ<_qfI@s66@PX5H&~`oq%DE9=EOSUXRCc~PVJEVFcb!AI^D?8vv=Ik
C@{W)CdieS8Uu{fv&iTohs!SgeBVHn{yP8a*nr)q;H~C3{lGhSIGj>8mmYll`o!uCu2PLOSJtdy|
PSXS}>Oi-cV{*Qx;KQT+cxCl@)l1xI19)C;76<CC9w_S?JsCay|;6Hz`*5_*Rb&+sHzG{9ZH6#T-
c09DZJ2aIRLdJT05&G_=xF>>>nHJ#1MxoQVz5Egqps%?5gd&_^6>UG!Z{X2kCW-)s}YsV%hjDl!+
>UglpoVmNTe<J3*UpH*51F2`q(rhg<OG~mgY4<t8wNIyOe4_9?yZ*Gc=}E1;Fej%V4sgJHNMH8R)
DZ~6*nJENRU8#^w9koC8EFemW)2u3-G+3m5oSxQip2c$kN*naK70BC^PRk?ak<^imF(E~RecS<31
-Mwv>4+>dUpF5FVgjSd5}_ocj(a3Utav!ta~-+F<o=klNz^2W?Jq5&bT_ZbiDKEQyc>1l?~A4T;k
GtCarP<`#4KeXmz$N7`u2P;$z!&b`g`WJ@JFRZICc<YPnfw59Sa$l&j|f!-WrH5!dwe-^d_^{jKB
u*Rso3mx#apjx0mXgy@$jZE4c=!={V)jn0qc@HpGdmqpA~F4G}%$6|fdZ{NJUKVWP$qvU5^9JO@t
j-cZ*Zn;!Xsw-F7(d^Lip=54jE$FLD5XFrNTI$G<TQ0%r2&4o)R7#)~4rvEVol>yV*5@cizuKWVh
Ts!+lwfG_Nd=JJSZfGKi-++h1vRq*jySm?EGk<Cp{fx=+2!GeY1tJww)0*6j;%0*5m2_(8B>$m)r
xjZ=}9Hh^bM_^+C%x~p231Zl8~U-0i+!u4qyB<!+eb<s!FHP*CI3stvb2$cey3O*woO&Wl%=m10b
`6sFBhvWHb!A8B`%z>;5dlfM-)3?@;cpDa?SC<mWg0pqaf1Zso<gOQLEsuQQcbhvoW2JGT^fGN>^
?S4PE_XH&+qx!0Q9YcaziIB(;Wl4-umE_j655KQ4XQAesY2Yi|AVdR40Gx0ck3LRQ27xM{5N518X
IyK`m9Ua=Y3Q>h8%Hvy2rEVz&c4}M0uhzlI4QsO1pVP0mPyJ3P52uKopzlX0-<m+T`N+kY)>lt;o
DTaQ7s|45xr$NCEN?F<db;a6iWjGoSvS9o&|hPjOo@UpS~+OabS~K8Q0+78`tvHod(HNx5H{a~93
VODIAYfN6Ih2R?v8V(EU&9uSmCQ{k?U#69jto$SXc7W><R{;H>t_-(7!Hx3mHP2eSVhyw)&-RUb*
m>N?|q2V5nQWRdi{rZ<W3@Y*k9{Zgz@SqRHnINBxAl;do8v%V;5vPWTPFM2?Ddn1|0>dEUzN7kU0
d=1X(;;ngDDmLr58T3*B&lf4pwo!po;5-!7{wUu3Zq7tFby{l{kq;?ipKH>ET^xD7>=W>qpDULA}
&{w18)zP8lA84*}-=JFR)$OVZLf%yLiJFpo4%mmXS3DKEOlEP&Tnv50y@JeGglCIkIame1)~E@>_
C^Qiue*X)Smir5{5yxR;JU_&G~ML4Hp#`X;gcd1LGu==w%wpnq@iUdZrPS6n0S>th_FGU!_4E_n|
E)XKKpz4?v=q9l=s;s7VoQ5AB*>^X!?n6z<4;nT=(Som#6QZ|Km9PKNV3}RBq2ux%aQbf9p5tNTs
vDf+_-t^Zp22gprrb!$HTB-#vdYYPTyyfxd#+-l(T6{GIn~JGBC#JbV3~S<jL9pqA3n0Or#M=K1A
?Co|B&BeLnG7b!F=eFFuaUZ4dgngV0RMQ#G`m)Gw-lK}v)XZdP>zPMah$d}%hNh9AZEPtK1?@x+7
r2*mtb*wJXMSP&+O~w8F7Qz$g1*kg{A62z`RN8!z-#YGdSJ5nq7I|xou{bCqN5^wMbO#irL*4LW3
W!qai1pbw9L+y;Zk~FajmeAVX9?;uj11V|U&U#vcfw%kCc+7&>4>hPty$I;RvOKh8qj2kg7hqfnf
G0P0)u3FQN}U57MNoNI($dV3i<%#?nQY12&g8<+7?nb#o45ALc_j|8($l@JQw%_%S)eWnV9a`zn{
H0erx<W8F$1E{tWs!l~S+Y*A~eE1u6AZ0}DH!aVWERktLKF!x@fK4pz_b3>aogp!zjEK2Oql2y$h
S8^57K<U1u-F|h51hz##o6d9g&mD)Bc1xqeUpy(pz><KlclR11XwzFtz6U!Rm@b$?rE)I*K#d248
8L0=gTJTIq@K1|PTKPIj)B9S-ER~KCSSZ9~3Pf&di5;^e*Jx28MyFES*j(P<T8?JcEh`F3z>wLDx
yy^kgfF1~4tEYidUh&7K_+}Fu(%Fb0!tc_f!hQu2H_B>tp%;PkE|O8I{w3*js<3KX<DSCIo`!pmG
k1piL*=XNRW}L2VJ|~%z8^NXegk0VpteNbq4BY+qrRmeFHQ*n2a?h4k>fvpo%?i&7OA0oUz}#{&%
RS(FlO3a7Q)gbWU$b=c23PH71vq+q;H~Uw3;00<vaS*O;7~%jU^UDZPCYn02x)Q)SD6Lj~kQ`mNA
VM?n#5W=Btd%fT0{2BeN@Vzc<P$gUO@`#*Fgj^-Y&Jew5;^EuxMht&D`QtgSDpY{`IOI$U-WemC>
wdTB4cjLd~ef`#!SB0gO2GP5rfpSK%nltu77-EiD6W&FH1IO6OTLz332u4)`$skqD$Hg$B^w4O4v
>P)!K9cDk42rI@n;Y@WuBu_8>PhMbrJ*`wAO&Y~PL`R8+{XF1eD~N5M&Vp;E(=tPEvzb~P$72Mnl
gZPHPAwh)O4=tU1lkbt2opnAzcPsFZeVL2B)6FJ1mPsI{TqJ2$JdsKIJ6zY?)Ul%n2HAxgX0(sq4
aiM=>pUB;u(>8m%`j%CLMbs%kd>7}3QD5c{Hi{hl2wwT-V6OWLDKP?Vx~68d4{-m#;%HFLmpxhC4
L%N;o|*C0^k1IYm6u^OYOR}(yxO!9S@eJX+_F*jh|BAjExG|_auiPCh-S?%<$)}fj8Qi3Djd%iX|
tznzCNm5LeHRVt)T9`8pMJC9S#E?LEcvlY<{xjO!!8jA;E<9b}sFzNh&Qj;Cd~M|3i}5?UCU2X@S
fmtiu?C>Qz2O3h_x$`&VMQK>QiN&ct2}7HIm<H6CZ;hy@E&+XJaEPN>L{xmU`p&i8sY+9+9JVTJx
MDSo1rt`(HX^KY3*A0$XN;hf8s6`Y@62A(Z>tDtCmarXw9B&Ic6NSQwf(x9d6luEP36Yt>WmDAy}
+X<#0{2R|)G=tj75Hv^R0OPOFT3IOQQv3VvemjM`{7yOC*PER<uXRPkMdOX?86*Zx@O%tJvJ50$s
7IM+nq8iyy>5!si&o?7gHMJQ4NUDD^|TbP(`v1N|W*V%GOOHzzh(!d{%yt&~thBue=h<N#$^BH2`
0-{EcXY|C&o0A36+u*)u5u>thM+{5TB3z>tY+zdxIOJCQ_wKV5&;+7Qx<2X|L#;(q++~!8f@Lz%O
3(g8NZ7UBA--~qGV$2&gRaq`=oY$M*`&#YNYmd@*yTW{hJNJ76Pu7|VuOhj(nErC)I~@sWHD10ZG
@=#n&?Rc=vKefBHbKGPmI8mE7Muwd6>?+c0i7fSYvEhQ0fzI!2yF9vLnGu!H9Rqd&$UuqZv_qfNv
J=Ho&|n&B_`oQEZ9702D~?P_*lGM}=f1FDL6t!8J!&p=c(2uiN?Pi&4*xcT!hOVxSPIK*uByp^2S
Rg=wOuNag#)m4mugH|YK}yz1!6R?$%E6goF33wOCg*(*ylOW^f;>8fxcNGtKKv<CLo2wl1Bsoz4J
g=8Th4$FjZd!2D~LZb}T4vTyq!n#myRlNna-6S-{OHZ?zwyS<wS93p)K7*o=hq%)~$}2pxiYD9TW
eY3Kbb)fp*=eQAJrkRgD0_8llZDt?+|f3=7=OM@6SfnT?I<;2*QyItyX~ws)Uh4A@7=WKY+X2TXi
b)M>)L0T+&ZP{+^jpqay|hA{8CriH?+#}P-|MfZ&;|^q*{vjRNkRAD0)A?%DPci+$igpPeac;&`j
7<H1Ak~YdkU^<ZpQw7t89(tp--N>vc;Vt{1vl#{hGn!r<jOTwq9ZVt-rQq^{$I7bonN8*P8Eftkb
Ku7t6HwIabQJ-9uh%`E3|E)I#WV8KLBM4%n_VhDMPa`<8Ddq;gn$@fIWRF%PYu%5+O>YZOd$9Oqs
A;M6#YQ&kiDmS<}aLTMOks5A!*C%>s7hpo}-nzZ^na1THrtmARYm@mxB6@aqdur0E+HM9?H?RfN8
{Ezuz{bb54lWz!{q^;lfZovo)^TaAJv}&;9frNsz)~F+Ys^GX7MeI(?;51doz9Tl-M6J}s^`Nj+n
kYwE|*Q<3iGUs1t9@(X*f&)p$LT)8*`hBwT;4%lS{%?lE+ro15)JY(b6y0TQx`Lr9B{dpGcpWO+m
^m(WWX=Mu^#fw7*qjg<{fY+*T1Rn(G>iP7PCYnB}sf!>~Hq!5Z;cjbX}=>e`@oD3v<tzNGqSZ0I@
~ol-DOm{J<@t}G8W3D`CG%vQL6_W(*(gBxxV)^BoZ>etk*3H!`-#5Ih&M>?A9(r(mkO|S^Zk*yAg
@=Z`^W)e7b6!hDT!K^Pg^Rq<+Ggk!^9Q0lDdXJ6iKpG)kVh%$-9SBL|4MTHZ0TTlN)vQ}=a|bAoz
WoPCq&!U
