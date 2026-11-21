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
c-ri}3wPT_vLO6dFv{l%5Ro)V$+E&&-j!`R(Y^8G*iI(76qkWWNJ2~k90HU?XL5i0)~jDYgQPQ=I
lJduN0CUNpVigXRn_(QZ7;r!%Xm4SC&f)?vECc(eesuvt77@^GR+<)*=?{`mp6HKaFJc?;eRiZNj
^;it`*GT^Q;K+RT<=0!6`jFEsCUk8&5uV%6t-}S(yiKp8ZD$8puA}q(uNf<xLXI)1pYT>tL2<AA_
rWNe>TR1h;8&H=r*IXd@`fe3=wM5>IY|7+Z$lL41+@9DMlp-NW}E-aQK@c~-`0mMnw2o4iPZS2(E
Pa+X8&Fr5Ym5%w7elN%_7<NW@=eriwh`2rd)lIcZ8MT_7jpG|Q@ad4TIZR|an1_YPjbza`!tD9t*
K!2;*G`LKH>lHN+T&()t-eHiIFpt?RzoQ9WWH70DTn6cUF-zu2Rzk_kwE!tNT`l7voGjxqDIPL3+
gzb&K}$t4yMlo%@+Cs{BD+trH2$&(J|@d7nLWIZ=TfPNTESgf-VnrKV!@OaXbFH1W}oh1NeS`+{F
9Xo+!YVnG}YjVXZ4=KO9uL@c$PfNr&v0_{56=v*A9HZrl058Rl1zR?BZ(xa8c4wikoz?fM?kDz#1
6L4qwy4*$cIRso={vg9XvOt<z*SErMR};Bj!9EX#BPxbQIO_m2*Pa+${2^$Z?_FO#{d(d!@dvBcq
{!-!`7HZRgL&9eg5ZJrRS0%)F{zkU%EFu0@@WH}=h;2QLf%Y2nyua?Qc%zB>01w1J(vR>!$*FikX
q11g4t`-3PUguFy9<5tJw*zD4Z=Yy7!Dajr8wK>ZPH$njd6oe7WF?^f{PH3L6acgWsKgnf9(30UJ
^+XqE|Yk<Org>uS+)@Z$vwPCpw$$HiqOCw?vnKS1`(&oFERwLhE)vsy2uMgJzAHK$t)@JEC^`{xR
Xaw0EjwW#&<!P&XZ1nSTMhw(QdfNG+boY<9HK5)+ET11eQm)xep)HEQ6wels74CS=e|8UTY6rWLW
zf+VZiCjmSt)=F=DenA{WAUoG>wvsna`2|}u*rTyD7Ez2YeZsXa?%vDw!iz^h-z{<1P8h117vl&;
I#U(=OB9r}&)qePq-`&Kp39n{3>`8<_Jcr`zWC??ZYJlP~L4|>kB`LzCqX;Dq5T=b&iI>-e-ul6>
MQ+~ah5lHS%hjYbU)P1z3hZY5_Wu0a*QXzTcy~5_fBs)*!Aa1)?;Un8vS;7FdH$c{@6JwNoV`=8d
VK&AVEUWCnZn22ZWr6(@~=-{oxO+WzcGpE4uXrl^9%r*PA~Ra{IG`)Phl7_LRLTS<Kqv>eF+;wKR
m#Pw6FD}Lwxl9CSD|O04<j(&;b4J5xo=i(NB-4L!>*ek}{qG3jB~k)dG4?%&;C~spl&=Am-2WS-$
)b!^Y5Wk85rG=(O-V!r&sC%z(b(K1bS{OvAJLNwUCcMgt+5@Scl)0krR*`-kTWu5l92P2bPb@;yD
04jFsCfB&ovR27IR)`8bZ(sKX;?BkN?B%h+PBjw}(8hZr?A&{DmK|*X4o(JP`nx*A<9OBv13J@e}
lK2mwcJLu!1OBPJ$*->P8~_ZeyeQI7$ruJ%z&jvJA+;NP6&%}rPi~UQN9j0Q&8fWId3xpavabsTP
b<AxmGIv(PVvOo>vyq-@IpW>R~Ztu2h$+jhhK2)KbS@rd%=Ssw7N3GX;nIkB6|Y30-MKgjrizr>n
O23IJc*Y@WXkAl`r<93V0cEx=-^KPNUVVx*#{{RppUhH*3=7?JS}4s(JGQs5g*Jdi@lrf;$~33b-
^zOoYnP!vkD#yHts^`ULpAEIba{cBK|I9J$5kaq$s~hrQs*6RI0QrJh@c2)&vMBHB<ofBG~y7~yZ
Lm&y__xc&h>P)~p5#v<&Ez~&ZbNbaA|NZeNhl(z4U!rtmT2ep0BUM4_9GZ|wQ?Z&HPDz4D4ig&O;
$6N7jbsSVt?zoO|G7cIqVSE<VN7Fl^k=Vni)$1L3DjxK=S3Ky~E2f@`w+ahPtxB7>fIf^&@D>4e3
u`V9dQkvk3$RJ`zK#wXf$jF0MU`bh&cXB%W{AE~R9Tr@#2hM+)kj<#&D92w5v$Ny5#Is}{NxIbHT
6_IJEvzhn4)Od9ohZF)7v<kB)<9D^e1Y@W~a4TdYz5Se4GJaK)bLue)lv9U9$f;0s#K^WA7Nc(Vu
n>7YQ(iGobX#!W_guCKHe~-|JWIdCY8L`|qnbE8*=FivzQB85hWOf|T0=;qX4b&a-$1%aANu#Inc
tzyaft1RJlsDYhTW%pTMLM*WVLz;Lecpyg5>jU?6O!C{T>cP+Tywcw{+3c_SSLWa>+`&V@AsJY7e
^Q(N?wF>a0Wz2)BLG-Jj-|2eGuN%sTPyyu3gH9Kjo$v_0ef1Rxe~<j#erjswz^>@!H|iMi1<8jZx
da3T7FbqU0sAkR4zwJ^2Qcicze8t;mhk5zDGco9{*EGXx6|qWFGACHuM@n7hT5=+6PEn`4kuy)GE
9&FYqch=NDylAcoNSOyFC=LNl?b)h6rO^tmpFt<T2C;!8l^#$oAXa&f{J$`X<O1N!AuM$Sl45vap
+*=9A*#%Qx>{oql-VnNI=e2PmrpA51(j9&)Q03y8>o>0w<0WTr}|U^Rz|2%HpDhTRLCw1OLeeX-1
^s|mL}2U#?plrvPJsOlA@4y!mHX<pXe2z1(52)5qb%G%e;y4K34&8>X$weqRf3M`hva-j$N?iTne
Si9vvIpsgO<v&6BPtM`E2CCkxoP^xWK5~5aPO{r^`@DDhym$M&hpP8ZpCNS`1%H7aKG8?d0Pb-Bu
=m`K?`x-RNQGMrEB^B-vL(nLk(q2bJD%Yg!K~|Iwn9bIReGOH+qBmV?or>n9uTcSWEQG>@-l`+ts
NQ;OHJZ~%TkNLL%p9!Qy#Kk!Lo`RLdAG08_OwF<f1zXNenY{So0wo#Frr7L49IfcO;nvT;Fz~CZo
#es$1k%b1DRneQpkU6%FV5L<O)Fwoq4~JqZHyb$Js;&Ag&n$bEb1Y?kp)VTqJJ95p=f9|9EVBtHy
oWdUR8bEQo0_1nnjwQopA0TV`DFKg5XL1@(Myla5d;}0ljM_M&~iW7>{SumO9$O*DSuqg9IK_s13
_Xx^a5~B_k_E2&clz=m&q$H&XDF(Scl66q0n~^S{AdZbk_ze{csJ9e#m#n8Qa=w+2j?>vpDXcs8w
E6SoW|e(JK5RJR2iSp;yQ{hq7N#|mTi4V*u~a7(5+LwAU}H2k-2WI=rNr)^6T^?qw4}SJrU?LoR~
vwXyx1%3Pov9eOVtW`qR^9<0*lH!|9&>epq2hb832dj2%)55fCaR+6!+1IVWqNZ7&gEqvZ)foX&&
E)_)(Vz@ay6}&|uTDh$~z{M67tZjMt%6rMkYT%5GXKK-(IGc3KIlg*vrQ_npd46s^ZVV-&s}nNC}
QrSy%QQ*<aJ9Ms`4g3hSZ&2SOQLpu(S#XnCf!wU&TdjP>N$4o`S%hlCYvUJJM8L^>MU;xCRMBOh^
qc8<RlVs&`&HRq~LaT>6Jd>-%^(>F4Mjj)afj)7`sXKm@@<@h*Lx2vvy4d^q!?*7)_FNSVZWSyR1
y2H3J-_vcD{fG=&yCvX%R`~QD=m)n$n0+WhXEj=9_wFdtOQVdto8os?kjMwQLS_JCN9P#)8pNZ8W
6WHxIatFa+ZuyOo%g8;*nh<omy1ua@g-%G}C=^Aa80t_K!w5VRtliNcS`}tV$=2#?qrACgNi%0Nw
z1kyrQ$dLOcuu&#gM7qERyGkAuh`XY26X;{+nqh`#lE7<H?(6ByN=?zyp=r#bOuVmhQiCVrB*ekp
|7kh*+&QehgRF_{X{KrP^G42LNuEGSj4oIe=>X@t?gm!Oo1QI^myK6eeTgel&Bk15cH)g^^Xi+7D
0!^fZ2mot8A=OlnZ*IvnQESs)6;Jzy$kaQiD3*QQ*{%D!?xTEC?cTKOJ;^NKn%8As#xuF#;l{tR#
%{_9eN_9e3TSF(RHK1Xi)1b;vi-7#P>9tG1+xP#8M2Npef%>{w9F)IBHvPDkGxRf9i(eU&Y1?C{A
q_7F_P*u!;56piqc(jXkQ-j`E!1Db{0H-gm*w$yj=H=g7#Cscy4LanBGwv^@u<Gh^^fwm7@!01&h
^2Q5qJ5?xFrFm%TzLm3|Aa*E6QAA>UU$4SL;(iuYb}nK>#sivk5E-PFO$mzqqNHYzkibkjJRuS_e
XT|+HbyMO3!1A1<3hJkjmmu6Rh5?Iv?532I?RG}=+G~T$)keXrN)O`rE?jN$!L53IVF#+9vB#ez#
#+Q86J?4!S@}H`#$&2zPO9Cm*s5uA@4oFN=<TAWZvb+Exrkva$%A<(|-VLv3z^0&_vq<k@Vp>3=y
4^uA%kP3CUKB(Mx~~;GqY$9j4_^HAq1Pgt0Q~qUY6Umx^$k!ERY$OZ4*|qdluS>8<93?0dq*&zyL
druvrGjfomGB<e|JE8A~H}xYn4^+NDK$=d#C+wD_9-$SxV=RH)NQ?pW_*9_L!}p=n5Mjawjl{Wjs
&lk+9VGJrEWS3tr9Q>w+*A!H~=s<vJ*4c^OqYI;IoIBePx25#<^D!|q6M+JT1s8g_+DO{T*=Y>>T
B^ioK1C@46lTY$05j{d;JX)di`yh)IA+v}+dE}l4S%RHZj43obSkD*SvfH*(vNJkEjYY|$h(XibR
>r=9+%x>VGm?Hns8L71<$FN^?E0Md^e!JLXWCX4g0p5ZYpg!=s!0}>_`@%<R)u0-IhN>};+>_&CP
j`uBESO&G(d6(ceV`|_ob-r3;WIL6fG7C(ceAs{%j?TWM~}i=wSkds3U7%h_FSTPt=~L~9PB|({n
ja}c*Jl?*Nsu|j{rVG%|4)Oc#RMH^za%V9^%7GQ}U8aTJ(oC5##B78M1Ki;3S-c_vItrxhEf%hFu
klO`r%t`0P1M2aXaX3iu7WDs$A2gwW0%Vr;Mi#^pF5X}5)DnIQPGaa;*p+tfL4#3U(O%@=Fbvt$b
g-*Aw1dY&yhxHpS1M6tZ5h7Yrs@2rb!5kR0YjYlCEF@f+9w+KsU0*Yz5UL+@#;wZNPG#vI78-U+{
#RVE8g>C4u9}NesU@&O+M%Hs_gqf2QpnTXK!kEt*v2(Zts9mDcGvsZwkIVP)VQ>hmDa1lQvYBB62
B`fN7QejXzn*!cZ5eJuEJ4L-P>u))b3zFaOV;KKt-;}fR5yeF!y)ladH~dTTQ_2LK8lQH<8qBkjA
fi%Cop20Ij6Vx*4w+9j{WM2_zb*4fH~|#@yMNo*7(dm^7;%(J3*QWDmJQVop2>Q`lc9;pSZ{TcL>
b^6^ALQFTGJzuOenk6^31YL#6)U7~3#nl&6h&wzxq`IpqFF^%5wYc7vzz(lct)1aPOrFnkOPk|K;
^<W^Gr&?6jrOyEupv;ln|N1pBwM|bGxQBy~cJRLoXMo?%7GweTl<mq#gqf~()J0A3oDg_z_qyYCC
SgyvU>2B()3(MoapLAvYp%AV=l2i2+FaT-nab*oBJ*!IJt#aV6l1}fNum)=#Zo!%bfN_Dns>5f}h
2r{4uUb5wB_&x}4ToPXWC>aUeD3jQ{|-T7KS8vc_|Q%oRWj8uL=kh*9e%`hUi9EE;lcso!bgJ(2a
E{VZL~wHszqx3kF?r=JB=NgPWu1c&;ic!Q!S0nE-adO7<mRrh3>Z$A_5QVx<K-Hh@-#v7Xn!#L8O
;K4nxF1U=nE6vIyCcgOR@~X~uA)i6u7fwuYhDJq_stY@rrEg59G&_2CmWIn?rFc%aAec+@ZuR6bw
oi2{dld9P=Us%L7vDvl2aip3ewAv^N%M6v<@7-#g57$RVW-hKP*R7oaFkh0>d667@a#Qqg{b`!g!
MKZL(=v;!}wOnOrS&r9Lz%RTdFN>DCP*P&xA_f*=5@)yut0H0JU1YVmF)?rEyUlOpEp$6iN;H{ZX
|EuTmzRjt0{F=z>Qp6`3VY>pUpp{v3}5DQzEaJ8rG=b2v$crRW#QbO&`naM0MPG2e<a$dVGqAlOZ
4m#UAKfIp-}OE72mc46UH}XH7?Aur$&B;hH7zLR4ek|H#LI$-^Y_N52<dP{yC-$IXk2#_}9lI`B^
b6jZE18<H2_2!4P7*^I*+f)@JU^^wq$FG5>|U6tiB9oELLls^GzBXMRg@TK^J8Yk}(#0-ReBHKD%
z39MGRTFjDgcYZ6<okzR2y))O<*!FI0SEaj+yw~SUBQ(rc^hcO4Qji%|!%Gd;!PAqv)@y?ef+mVN
5=CsCHCun2^+Tk#n4m`f?H-3poo!&;@Y*EJR>}WWTxR&kxy-16y3)M{uF-x#$J${tHyW3N7|(jV+
n2MM`i?dlIw0?<t^$}G;eqI}kg_iU#6dc?Y^t;oOdkyx-0OiBTPo~!2k^(${}~K}wg05_Z`AXzfR
j=RewV*i_w^OcK5O;SWzwhl7A-z>Ype0qB{^|B<VnolvoR_3sYws3TVcNr4(i;iIl=e}fO*M=3jp
=<kE#Dz1o^X+|J<5Z{ij!fR`}zIgZqq`MEN2^ly64U4-atW<cFIvo-m3;n}Eg0r$7RLJvczxp;~p
#P`EIzfG)79ZF60)<LyB8QlX~duU;3_?i26|fd+}stRdHG0(Za{1y%WyE7T-RLMryc6+u%W6G$MD
b=3gU8yuJF8Znf=tzgv(Zd<`*2CrQ^UdHp+AP*$yR8PWQ@Qy$SdkBccHSDxVO!s?e6+j>k?v#}iZ
Y-q8w9Pab;hs<$=8qJ<p+G}@Y{oXvzgxnAoMzV?jsZ#2m(bWcxg@C=KFIdZ(1Uvgh=?7sCjyWJZo
M5(r^*17uAHPzY%*Pv*B^T3FVe&!PuyCLp(C*8$xV`cEd0Bl?k5zLU8;{meJwOn`@y{7tDw;)1eJ
zw;vz1~rCF<sy|Kcg$m*_ho#5rO^$wt3IRj1qx)@2e=4z)l!j@G@Hj491ZIw~0`Ka|Ay;56ks*y(
D-CH3%w_q*Xal}YpAt1h)3$=&cgbW9tb9DVO)G|Jrq9O(jT;~h)C%wZ9dRAm~S;db}@#_i$Fmx#>
1KsT3MK%Yymijl1^=~WnZ*=_%OWZt^6?Gdtz`l3s`j)zZ@;CZ6mA5u*7!91^x)t0Tz{Eglk9VN3;
SytEJbKiDzOK#3OZBm8<3Ls`9$w~y3Z!rum#`a)fr&5?DnBG0dVviXkZF*x3$CdO%t`ya+j^nNVx
`RiJKAGZUS4l{X+J>+A4L!No-i<`P1S-bpvJaxFb`ib0tVZeddH>M#O4y42V{F|ZyeI5f~B)`taI
F4L7=yL$pXXJK-&f~XoF+{=PByq47oH<k2f0_ViONlFI-7DX%ek0J43-s%hnLZu(72FGsAKGWNye
xE}eRphh<Y>AZkk}PKLI(p91uT<rYmZ%xFuY)$MMrG;WDzlyMFH8W6C)_RS48mG$@nN46WD@%hM$
a)s7Dz%*gFn>C#O%Y>cOnWaVbdqIvgit3>6N#^(*(gJI>JGuTTy}6Jg7%SmIU`O1+_sKLZ^QG%^S
j>TifkG7is9=q}MF3!+jBs(b=Fm{&RRSFXh-R~O@aro3*l{c*EBFBd#-m3Ev@INzu%2ryfM?rHDP
uMzBWKXsF42me`$aM-Nu3=Y^ilXl(>UD`xgn8c^iuvgQ?Rk_FDJUO?T%cGRaEc6G??ZIs|n^b<_8
>cC)8u3KpmTzkq1F&4W^|*)zX8C9AtY1;wie3!SYN%vV{W-t;W!Fgzd*@mnV4RgAN3MFWUNz?7Tq
`hN89u))yR8OdmBV`N<9l*VIG8xfVV8;m3fYjgTQ6bHrqP*Kxdhv5y08m<$>ZJHcCPU?BGiMw1)b
B%kFg!-JZZ<}z8E9C}EiMcJw<ss%!(k+3j#H{JLiutgd<34B^n#0OKqcNBUQI<Tk`yJTZAGGg2`7
NJKH>EP(l*M<U_(m{f3`Y}b%B#a|e>L^F>C8dW8#1rey0B5ul2Ys=}^TIm(2^+#m;1m4&`)=A;Go
@btm<aL};sXb)`rIkrQuKq(Geq|Cv!_UvtO?@x>I9n(3oB4fK8a^r&P3EjSjB)q*@SghBE^;GX+g
xvA)b~~eKlA_XuG;*6kiNWxn99x(FzXw+G&?Aq^*!UO2g!>WfkQ3Z`;cWeP}M|vJ+KmvAV53`4!_
_R3A$0xyn=SdkX=wm#0R7Q1lUai@R<GX&B1>cPLfz!2IvY&kMomfBi-95+P^2N=c`|zEV81PVkCD
0!}$97wS769UrKGm`=n2Zt>u--#R?(YZiu;Dy%gp%`TGt*<HLYP&DK4b!b0uvrH7JuQn;h(_D!;C
uJtU$ChS?t}u=w_JI1K>t(VAo;{w$wHBAjVwSQhmjZXb`}SE7!uCLYR{sF6)4Gp<Yd?-U!8wN|D>
!r_2Ii|xIiE~sD>Q3(s6yod1)2ksfkXN=iL>I%U>Yw!qIyenb_K@oV!kZRvZOY|g1p~3#AFV?@|l
GGQ!SyM9af_a?3xNi8B5Tkvf3D0-UI82PR0nGpU5bGo=%oIYGqUq!vf)(NeIyRGM9EUfODsErO9Z
oD6HU$;8>ODCAD4S*&~Xv@m(ST$Dm~+U~1BgLSj@R7qSU2MI7KjH3Q`x?Q0Nu6-2#d0wt5>0$6n5
eV{@qI=eZ=%jg|FL@xDFQ2c$BB%f^Eo!j2s4Xh8T4jG|VLATTEbvoTn{}92O(7p<;;)%H|Sz@qP?
RV`k1Y3E5+pQ%K?E0e7b<A1eb&2!jHma@~P(@W6TdKSzI;!3;8mJ2HK|6XUo!UBtCq)NEdVo-<z<
>#`9z9!%cNN3l64UYH>Vw`<^-2FwJ*m!5#$oyh@0?B|qeYTe$Msj6c?79vMpbXq8lP5GMcai-ix)
uFdpo~i7el8tS48_NIM~WHuw1!;Y2YrbAQs;9xOe1MA>;t!P_3<KNtH}k6S0jHwgXBOCx$1iT!&}
{3G#0GOYPP~k#8(To1j(#HV$*V^;eoRB?ef1sTE`F$1?n>RzPr<u9IXtRf`CL#v<~uRz#qWMdYJZ
<aZ6cFM?CD5G*Ma6P!C36RA~EaiQ~9%5r3=0#2ISQW9NNYt<WIb)}Z7TM%L`zAQAEoG0^qsX`OU!
wm{BXJGbeg6?U%vEyzTR~IBMmONT#gq!QR&~VF&ublQm5(lIj@*f;jsh9$XLhFqVe37Fc!T7I%4g
))Aj7y<ZoQWOTL7oh|qoJ0Z<f2D^bBqhP{GaA^N|C(d3E*sD^!ljq7z-+gbk&T;sIG#aBIOcCgRZ
A&E5P+cZ<b~{B0KY~?EOAXipervaKL4X)b6PI>2yB{@}h$scBbhPI|$YH__Dyi){ra<#|eg<p2j6
b(9l(I<A>NRN|X{Vj5Tx}imAL8HJ&|A6WfL~9$%$!42+|wv7<^DPSrwkpB7~i>fu-UHj34b(auZ}
?1CikB;&wjCqOOBtM)NoBm%c}<+J;l<`V!dj-`X%&f(QfWef0V@rE&<$o(WgBGZC=5>?})@|8Tfs
}9kT7G3Q|Km*wnQGBd%HIfWiW(-^(a)WruZ4Srx>!M8NXZI<&<K{sfcmWcXK&Ton{x@hs4G$(`3X
_dN=_&TH==T|qah7936++3~5Lpvla`tX<P;u<`Ki<E2?e=)LOv}nu)&Ila|9kM4>C{Q^+wXO8N@F
fJ;290o9#(K4sdlKI$^8aiz^g}eVC{|k8;M%{ckBylK$)m0Ol&FLGfqV<AsRK{z7RtoDq%;P!q8j
DKV$^7OqWp=VWIBe+$4*WOnn&*9Rpy`TseWngQe<M&8`!mX$$26L2bx`f`fBs;?|4*GqTgbv>;~h
XtD~%mCKApl0i@l8i1geK5V?Y=@d!wF{}m4l2wHF%y4t82yOqDk5`K&a+u+w6|5Fx4D;&Jp|_O01
QSd!PxNzpwQyWVE;+A6aU&voyee;U)F=G}C0kHFo-FeMM1%ioPk|S?8Q2LbFx>^UAoenno<fupc8
&@+Jw*`4%Q;;Swdl%%@-OgxJ?5=Y=6saAq7yvh#1$g-x6=aCABfQ*WynB94e|<TJ>)UZfzH=0ic)
FZg9TW4EpV}S??xvQn*}s=fNGJy&L?jjtN^{arkkM*z*;$?^5gvS*N_oI7%;tvCp4&*mO@TYUG1*
y-{RW@&Jp15-#q&d6KS>3yuYoDX_+)7ElUHh5CLsOfBEIM{N)!^Kix?_3pAW$-Dpc~n1T)Ym|@NF
eh4tj2m=Bt-mM%mPt@7;j1!6wbBGs6`Jzoh%yU3tOcRrSOoA5&F9;1_PEbZJ)$_8<=Tw$@y~WyBG
Y*)i6_k3?s7G6I><HQ$!Ckx#mUt2C!432;x1|*d>%ri$mX}H?CLRREayCmZ6{%3=mD>-8s_a=_GI
YI|W*$aebb=@RYUs$hqsIPov1)iQr2%lAsImB}NMOWU>fk^%qUym8ZIOCZIkC*XvIvoG!w{rO+<J
F#x50zX(Utkd)K@j)1o)(5n1&?>G0E~|0B372IV`bf6Es~}f}~Qe=(e0~BMZiDyG4%2NHo1b`{Z~
gSE&Vh(Q(V9PlE>vALy{M)rYIwv0@LpF5tD0<4n)eN5~}Wp%1yHRN!m0hzXRwFcU?pRW4Pfd^e)j
D4j~`DvgHX@zkmKDL4#|huuMQQ#8FMCPwv1;nnm2o{)hom5@OB!UlDz9JkKTyQsA5c4~eaRb(rxh
_)gVyPzH1+Ev-pN9_QuiK$#6S$<L77L66^VVuf-D>$e!tX~k3y)CO$)euvgifIz6vM43@)#kWJ8>
!<>&}$=JPh0#=lpvC7iOCPXuc&cjGVYtuOevf!41bu8TFzID_ga6{uX`Xhu(XvG!1N~%A587vybv
%L9uE!)es**P@-)vsy4A}{V>}ZM^X8#(QJsBb&h2hj(E^w?I^JP87np^Kxknl(dLPNt8Z!VSy2=d
9<HZ<>i0AY_HDm@6O015cuy9IVI!9NCf)0Q_=KTNV7u6MW05&S31jpB4z)QnXpWkK5V+2lC!!4Bg
H)QfHia-)t$qfhZ-AQp6FMwT`%?cO-)K*5-D$bgvQe<Xf`(eH1aIN4*mfY2jLEo|4e31TUj5LP+)
jv4e_G(4sYmZg=%7={=i$B=o6v^7wQt52Anggq{=NKvNZ0n=UjXE{+@|wry|7oY38K+Z6Hy3R^;D
}S?O*7bd=wK;80L?9O9b4HuORo&>H+ru5n^oH62i^X(Go5lL^00Z~^#uQ&bZ!p&JTwW-mIZOXDl1
**ba}nPAfj*SO=u}~PfWhgOsD+B)DK#Z#=<>`^LlFBLnoe2$FVdGL*+D+ILBr3_f@(S0~mCqnJu6
rPx{HNEmH5;BruXZTn4nx0_XcD{l!{Q2vF}_cTC!daG5NUm^3l-WO<z^&NJFN9?Xcjr)NZq#1t4|
hJ<-*3#$dCj3FIYauu&;rIJV|H#we^C!u`5*jw|TPn)!cdb(`M!1n|9oP`x+weS+KO%xFK+vmptn
H_+W)_+{WN?J3YrIH2IK4es7=>r-r$k~*-qCePKVXh|?H(b^HVkt^-q+(<tyUz#>JB^kV$=Su8T2
akFf~Z6@c`#M#MWBg{maut=k;EQM>Nhww$9~gt(xjmx3_G`PfMz)w7ui}lJziHUXW5mhVWApKoG5
K&7;#L{u49ZKNo!BsP}x|@A(hm*gyXMkMpY=)TC8jxMwLztUv+!nD(1$6_5sk_cK@j07EfR{)aHq
r)(M{fP00En(6L>u?38pusOJ}ZZ;-=5l=ltVjzSwb_uOKb1&ese?2DNgUFD%{14q_@8`YMKl&PlI
5TL5lwG-Mx^K$aYYS*pp%4J&AWzum=eykPnj=|x=Z1)`#EndUIvv@p;tqi$yc;kR8HH?tPQ3iaWB
=jay2O)j+?0`W0;YgO48)$|_L|a1*uZ3T<X047<fJrz;1{<IXn<UWq4O*z(0aV)pkI@jSmo0k+Ev
{2nv8XBBE%TCSp{gziaf+E-5EaH_=Ag!7JeS8~t<U6R`XbwF?ExFH1QI(&*1y;#E%zB$P%afeUFP
?}!BJNo+SCp!qGNPjh-dlrDp3(Z+xVK~4VFxvQ_f*TJaP+_w%dF{pF`R9ZNE#QkIEc2=M80MkrdS
BU9QrV0`yn7I$2tBj$CC=ho_B_UM>^rqr}YM%y*ztnNy!GS6L@eNq&)1&j3Of+3EY|=jT{zv09@3
dSFT0Bs3X!(n5u?1q6Ts>73^GbG{0uxp;-nW@!A!mS{@aq65(~aYPN%RX)Q>wYADgcY2Xgub3$|A
#=!fdzt5@l>(XF^k-8s7a`CUDIY&=S_NfYh|)HU@pT@&0C|sc6rcfL@FFQbmidA|=My@Ti%#%XOc
8m|8kW)paptRx(!nC!(3}UPhzZ4mCnp0QlS+Kf$yfN4?UcoB5RxvJQEC>i^Hn*JBkUr3a=l8YPdk
_Br=Ox7<wKGp5HhMgd>K3p<V?1ZEI17?_xmg{4=*y1L~;x}@Uf80Ey+C^qo$NUnI??h5QPFSvS&p
SFVQ|TpC`P42tIOzjxnJ#qGV1PUV>>_Omd2E0PO(tIb(n5(~L(TBSe_|g2@nmF`P>$ct-U6Kqsz8
qQcJ1M0W`~ay6N;q|XOHL5b$c|6K1Shbd}VXs3LTNX%!xmcjzCSp}=~<+!44&<Wn#8EaBJ9IWtHR
mQ;bvox{Yd7KAT54tT!3HHO7&Dq&oMiDZw2sAmuRPt}Pl=9Zxg<NFfk<+qMoQtKoo7<dK_Nioavs
ELU=#5tNha$dK0vyxGph`^ZjK>#%g3uxbz@UBDQk9^G&22s5J=D&ZZA9az=oX1Mfcro;+s68W%r6
EP@Nc@BFWe{S35U~q!$vkTF_1K1<G(n6rw=X0qnuB#AQahQp!!Ruk*<09t9v*XsumiYGC!`)Uf73
Epr@w~X}Axc;D$#TM>Unr*1`FUe;}Jiwo?o;dQ66pl=dF!=Tew-5v?#=iyqJ{ox>h~Z4xBp3kkmW
n(3M<nB{FEG}?lI^AF`14+x*DatuBV93c{P!U(~$VjNHub%s_zVvBExD8IF*=~7xXyVgDFg6rG@e
f?yMRML7aF)(!Xfy`zAbjzJ3N^OI?3*j&jVU<EAv}BvNg6ky5#ENUXL8iyFTnktNwoG5(kxqhp<u
#H^5VG+0AK&0Jr!i;kjS&coyD%f<e<>g13gnkAQDZ*L7?)Z=I(a7`{Lw8F4fEB3r^+0vCvck5m0|
FX)dYn^R16L}$NQb&HB!BFIc-D5a!tY;Y<SxHI&+>xr&bCM{op1pZf5DF{!W%K>Pueek4safxLK9
y%zUMYE#~XmRQg0MUu5U6U!46!xmT*kDGu)Z!`Z9x*-szNUcWzo^ZGqnm|X1PIVlDYqS1)Z8t~Md
6coiHB~A-{Edcu{We*c@T)&K2J^{x!!QK5^48cgd4%<?2!n=uYe>i`^O9;#a<=)`XlO^)G`bLBVT
nSit323}r!JfgJ+~;pze>gpVefDnr>h#<5=M+m&<r->X@OdZ@$j9%`e>{_qZ_nSor-{A)&-1rq*h
o0}-%xCtCS%1a5)j7Y#d?A+0LU8?RIbyKKiz`xpuE&HX{&2{F82PvcW2Lke*XPg=h^vdF3z%A@MA
thU*q$P!(U*!yS?8pvR9`+jbEI-{qP+O>cBBM!@VCWR%8rBz;h{ZE(k{qGS%o{gj2=iiZ?D(AY>I
SMvW=MA2B;KHeM1xLD^$fuGQ_a+vYyHxDv|jg7r2rVxiZJO|1z!PrxHfM?xGJCP34zI59#gV`SZ!
uDpphS*AH-P`XnW@)hegIt12I4M;z*7<g}3>B(;jZ3Vlx`tU@BV~dl<GGbTEh;p`E;+`$=sn4%dj
dhVPDC@O9vz}{Y<p6+{52zrSk!XP%m}h~xfgcpxysMQA&ESPm>c}Luo-?!ODq|qGBc}JYlMtx;Dz
gL?4EM!nQykcXLnAx13}9?2Rwz6c!E<7bKIA!uV<J2wsX(359j*NS6D+E=;9%ko)A>F|E~5x5ra^
r9CLw`wKCQZRX95R{#3&q#+I}dSSk!>}33&5?usyk(hRVa^i{N9Du)z(R@}SFiNR<7*u{r1(7(Y6
0r%T|frYrI8E9BA!869*^P|d}79Ao~Qc!r$Knm8gno#jk`8n_d*|32wFjD1pxu8QSds(9WaNwSLC
lxB)z6VA%E<HF~4YJiWUnnq5QN()$RE;Fe5;Z>s{qOvDjhujZzL}#fCr~}N)vMdmAA-~wiK8j?)t
_J*!%qfy=dskRWJ06$`sB}b0l9{WSv>59{KCD|aQ<SbNV$fL9rn7#{r^ww6vTUp>xibE$WK3wuua
$sV3U~$J0$x{fufyKRHt(#kDRqN89GF}<J2bO?t)&ewZvf|J)w?xmj^DAZ<sprr!eyx3RYXPKyeA
4;9~Fg9bAZc?XUKeii`5U7JuEY8NPF<brfDhy4>;tknR6VeZb;)BIrjwIvl$x-oHDwCu%z%MxD<H
>h^VNJm>Q6TiCUI|C8SR93<<4R<xxsolwX{sXHvY|Zu}?q871c?gVm<(+yQ)rGa!^5)*&^%`sS*_
C#xlrqZUx%Wg)9awmU`VE}nh#4hf462WY!p(0Lb5sVP#{;JYm+p9+L-(*)o^35NlGQ)R`hx!B72t
fnqQ-#A$`BGTZhM;4}*o}L7nH}#p(>)8(LmO%#pH6Wc0;9e%6(53vAxp=fof2%D0`zom*mg4-VRT
r`7l>m|JRt?nXp?0D*T$*e_e*b43@OZ|vuQ}Q4Td~mivXOV7yEoG*`Ig{GdYz+xADVwn=`Zbk=47
hkpEmj-FW@r1Yy%F&OY(i2pj47cOaRhIqL9YsJJQV>L%5>s-;w}F+W1>PBP0FbIkhE<cofUUOcGo
CvZ$RGMoq19bSmWr3U8Qw{T8FUeMG`*4F_iXjSO326sQJ%VLlKqUNNA}FG|aKfM)7hLALArR|%Q0
<Cf|@?9&_ee8vlS%k$Z$U=@kMp}0iIRir*~x-`xpo>R$hYyr>kWI;1<422M*s@#8gA(o@b1){O{W
JCP~jsXiPDxgd=`0%B#WzFP8C)0%b7*X|b;ETWRi}s9&)4~O+AS7S2mjwk{=1)ESsjoj(gFE}BA+
!D}Zw~e6I56wO09JEM$?GL6lMJd?m1^W*C&%dO*}i$sve-kMJ2~uBb|v@kT)7J!k(%a6#tV(HsUB
jJ<8)f#$UHj|*7%kWrVabdIgB~*6{^}h^f3f{{9oa)+x|LkU!AsJj($7-J!&I9szEqIr-+qo%C*c
_i?A2b0*Dbkv`ogiYzU@i2YYpvOv;c?1P`+zVa#%^$0aIe^w<MVuH8iSM4)!2X?CKek1$*X9!8b%
C^Y7Xd^KKGJ-}m=lp<0)0@SWCZ$q_$t;VHo>F`7dYiVp`T@Y_lK5%hGd#Xt|bl+ipLlTE8?1^>ON
dFz;>B5>0L!fE$;Hn<#9c+of;GKp7J6e#jM$)l2sqdPqDU3`A8b`4aSw^)wb=I<(hgQR39(pH!vt
?;9JxEiv`m2DETc~0PK6TNf8KfJ=zlG$mt=(m!_%z?<JjFfOrn4rVND#~`I8#w?A}9+7+-w$H0~H
EZMU%kSxZh-O7kfQo4_mGclB#~4lxSn4>i?5FME41ODdPl-4^!q?_06FalPa>uY996+EUcrSH~+(
~2<R@L9xpS}G)@}IpT~}B7LXhK8?Q56rNb=cE?otiq>xmZZRNqiiflvg724NbWUt?R7@z)l`r-5)
T~6>R%Q`u8&7d_q@+e@Nj{uE6fU(R<zJ;G9Xp@XyAaO>@kq%$H(5*#gtWV_D0puJ;S9hdSW#K?J6
MXyr{=>`n1Y5Mepqq;iX*nb7TtN^Owm}<LFn1{z9&E1x$28R%1f32HjZQKE0XFVjT5P+i!16E7-@
pC-^k=d~Lu0M`!(NY+WxYO!o8#~vm}^@x)IWT9+3p=ZJ7ad9h9Zr9IREhdnQ5wb^mUIlZ@%hM=ex
7h7iYL=)fV=tmLVp<!}g9Y6UyaTp&+k+_`Z#?x5yuBs(X;QU@?0DRF3YcF--$l&k}mHAN0gMh|-R
d8Zo{b!m9zl?vF5#4yGW!xbJrPm+i1grA~srv#qcRtUv0o`B%scIi{kJpo@kZ?=UNEsZs>X#w7yU
r$keWpk0p<CySf>j*yBm$Ar&E;$SwHD(?X2pVN6!G^`Ux=VdK)w418SiB*p+4hM%Lt(?$^zA+s}z
BFN5g0P0|tt!S<&T+&7>^VXug*3!CS(z{`49r*|C=Hh@44itSx+p|-2aOjlC2y|U{B(ZjqP!}`cp
w0CD=7l$ZojDGh^+LNd`X9C0CAx}xXoABH)MdrE;*!HlU68$)q+F($ikr&1>Q7s3Cy0u3S7Jmq$f
aifL*7jNOc|}y@@&-vYG(R>2^1*B-2D44ceDh<f)ZXq<epG*flJ(IL?N4EBhP*7^86gH+_-}<G`;
F<vMu$wH_)x+z*a}r)JcfMyt<mZ~Bw(%s8dt12a?>s%p8wC`E~sel$?y@udb6_EXrXWuW3K11)X_
v6}mpVEH(|3hC<Io+jScTgy)7eV54<MzWT~I*+@Y2v7{PVh&KPheJkUc6+4ep&R~eHNQ-jWS3Or0
JmhpQ74gHp?L^*iIy;(dh$kgAmjm?4-X&0oKH_N$ARnz_(V|XstL=kak3Ix5l(buAoj$phgL@gYH
(t~j8|`;YubTIZ&ukym1%~m4Y=~YjA&G&J5+`D1{Uz&D!86dYC3TGP;D*3q%%iZ<e3}xDAgl|9PF
QgD^jdU*F$AEY8%1xusdL%0z5e*d1Sk@Qbr%;j@!NO+rc!*T6jixXe#rMNm*oJvo0rWFnvax?jP@
RFJ{`VQEpY<FZX<*O-S7_>-h}SXsm-hE+%POJ=86%*-FExX(nQ>*sl<-LL4+`Uk;#7zbRp$z>@mU
CCK|zCcWJ{hIs^0)LeSDib5&cwHl*Bm&y`OAtF}=-q_tiYFl7q)sVK>|GsP@mD;SfeF)h(T#AmXh
Bb!+9MH&>c6et9Uu5xHDJ%)eA)#}fU`|rork3qqH6PU?Q2;5T!;MYIKQ(oEP`Z$$SoOcz@n_f&u7
0~_?ccjt=xLw=&=?ylcFno%i;lzPX-q}w+)r5;j8bICl}4jRl}PQ@r4mu61H3O^HTkW<qD`Z)V&8
aKAmV_is3)<D3Y5iH$5(7hMnafgFDI>(vSeU6YXX8`R<T#`@h;c~;pOM^sDKwF%$`&jS7E<!g)t4
fqkR*CzJd3vZTsr|uYZp-N}tqsfNN)<jLDThDd(}nrvv~TvuiQ;^M`NWxu{rOWovc@BKjj{cr&F`
J$Y+m!t!!Vs<KkRLG;9D!-9L0Obm@~;4-;Rvy4I@mqKe1Z8d_p(T#}7z)M;(=q<1g#|=UjKmt3G7
Q;#g@ey4uvqFchHfawFu?Tj|=YzIbW(d2!h^ORs&?XZIj&QRoJHg*LeYf_H2iXeM+lknai$iRY&^
=kMT}C*r^)mmMh@+V2N=igI594ysbu;9#p!6i@Q)Uk>u(7PnsIZa4kBcz{<wQRS6dthwt}ik=#j_
yQjyl}5WcX;r7XlZ1m+7_Mr&IBn!{17DpyGWzBl*+8$YGm95dKe8P5gMwH+cBbG=tAK3IHm)sP6E
H;)=L)q!IU=?p3|*d^(j3DM+PfB>VyvNe=|`o}j1`I!{!Ku6V_5D<E)|T|IeM%&;nMf``b!CxJp9
?&6@^0G0kxWGiXx)H|%H(L%L7@+T)=@yubqt3tU|-{!%mjD*#U%-GU!Adnfg7$u#A1gqwHQf*)Wt
AXliN^#tqnzEZ1G_04W=`t@Vd4q}pO<kGS3N|M;aO(FP1R}Bhlcv-+YOp!5tkSEiHQ@31Wou7WGd
{*5svfxtI2UL1<;0Yu`%IxTg^56}Ja>s&<0iQ*J#65q4y-_y12KCrp>q={QLH$C!W2r*N<KUR=_!
Co#e&JtSRq0E?ROh2!i(4VBa0qm5mH<o9I(+;voZpUwtyUni!f)x^`F(oD#Oc)DYz|!AE|TBd_KN
?{cVkL9@q{~<fmc7CRUkkJ7`!Ivi|k>YiQ`=Vu?lv7x%qb#f4CO3Ryz7dz(lTV~f-9`Pu6i<lkDF
rl{Dqw&Z~lP*`7lJgRW2#U#!=z<I9Ysfy=*8RNmM15p^|9mUDv8+VH#F{(StGj^F!;K`KTUo7W3e
0hZ)eQ*ZQof`&YluQx=YU3+tIbjrV=#sk=qcJIZfDMV2+s0kI?gZZ<rV+=6T0(BF!ex=g)Hh;jLm
9}>#<#GTC*qojY4N2*ts??67m;fP=qUDM3Vz@2scZ!B`$=$g=v-*8Sa08}5|TPk8CNWJldLL4k>8
+=2iEp%8b7v+>B>BMf5qW@sF2*ADJhdoCR;2&Fei!WLtM!Qqn;Z0)|1UPSc(o^5p0Oj9D-2Yq(;?
n4i;&u7>YU~qqRBcdY-R1jJbue5An+27}^PINa|f>ojxJ)neW87+NoHpX~XXcxqwSRDr^FMcEv}G
@9vmuCsrMve^fwKrdkYe)fs!h3<QHM_ZM@QDml+BSL@XxXbYNJ-b{@DQp89F`XsU3m+=1OmfRxQS
jL|~*qf_bMWJP|m=kEmO!oGW&~`LvtTYzISj~b(3=EYjz#MgC|JhO&`6x7^*NPNxk=R=uhP;e6hx
a#DIdzK-?#&YszkU(r7m=OtgVIyAk|yO9V?OR&G<>_c=2Q)p$;80~uO^T5iUEW5_DNt}ybb&Y9t~
z^o1oHM4P$)q&S3nEmrjT`G#wiRq;Gur^7+BnkNcfYhrMHpvYuk+3)!_$lj>YuP1;zg4Yg<^pz}5
bTVM$o=xR|<tV3>b9<v!<1z>tQqNl|WK&+U;Ygh+gYi7&LQbEHi>%7pZjcx6mfZEzp-Ug$c7erl6
x_8J1MgGuzBqf`db(R<~mJng_MXjo;F1|{}Jh_lss`Au-gEKL|E8194Q6nNOa}Y(80~OP2=e`;Pi
<7lsvAPVGUk;x<9bD`^L@%m;{Ex5blD>@`;??L&WedlEf$d|(EUPqwJZ7=aKqoT_e6Q~3;gN|5rh
o(Qhl69ps7fInSQ~qtjsaIgicu}G0qUpQa+Q6l+__mFJhcu3jtFbcKP_HxoHtup^+t-e?30H$uPG
a?=u-*}W%zl!!f}#uK})G&n6*$FlWnr!OYB-Ub<$p26v+V($Hht=X~1kIlXz7mwQ!CqWCqU&4mGm
(qSzjuV~wq+7<$Ovc{p>e6Vu0<jek-Z_rHYbOZm#Af)t7^;-zTr1O&?Kq^y$sZ3ih-#~cQ7u+@yt
R55Oxf)4sx*fcEXTyf0h@H~`;J&~6@_GXo?Osr}2A@9ud+r+grBNQhyvz7}L?p2wfxh+D$<y`e<$
1<#iX?6O=u4FR18JK7Ysm)83Eq)XT>ezVph8x&XRw>7s+LMcP!uf&XHOfth@@OiJykVUq)#A^bSa
S;W0RL3<f==)~aixqQPKcrW3Z1XxOwCuKQ(S5C(BhpK>tHkz{lE>Rqpp`c`>c^4tb45ty>1H^dpx
1Niuo;uV5mj)+t7kku*3xl;4!{}85g01cBxZQ6*~gWDChBVtv%Lt(kT;~!tun=i9qR-Hy$ke0nux
JP;+H{La|%0Ei>C8MU4;V$P*4R&en)qqaaY!H|&^0_+QG!_Z!Pq!bfxbL!CTI*2$IMezSd$Ss28G
U=*>^ex(vP!8;uk4Iu55v2&x5XNQc;E@Q<q8<0`!rVwjhc)RU!&~Qnpb{|r6tJ|n~rB=80GEso{Q
DlNpb}PfxsjZ}aV~4wIu-R?A-fq!nqYcgYq0}@b9f_DGHS`52_O>``*)}_5C`)NSTEQA5SP*%Wgo
1sc{sNVfT^+oLE|2JP40-bmlcDrFM;!;fXmj9z_>=VYyV>U$3`Bx8aRNG4!qCRAMXt8O6H4Ze{4Q
(hSRfTu)ZH@XOb@inR1`7NSpnHl1Xb7>3i=}frG!EH{=a?-CO0u@#I(Pv4u{&-8A$d0JVjiSC|l%
EE*Ejum_#o@(v4Qr=nA4OfMX@kCK7Cm1^|tkP*#aAA4P=^z|6C-SQN{^3W8;Y(Q;#EQ9&zk7B%3W
v{Xc=j@)9=NkJQGfweu?<FEij6?%aa%^9C%^%ilY>D?6^eVFGJND>#3AUPdC{GLpsbCcXp(`z`Sw
SGcs(`31x@4#u!b;se?3BQ`$-u0CLUl<@B{2YAv_T57lO<TdQtLb%uiZ-#)Bo$N5<?3JLrylC-`&
Lj@wtl9&Iv>Jmkyty~h08k%S|!}eK(-qzwHLEhq0jS{5<_611?_awX(Qs>+zahq3c@4q9s_g9gdk
B7dx0E|R0{VQe*Mip6KNK|*F*3qoKz)z%b;V`(dK9fSm)h8_3$ZQz`iJLVllvZ6OUP<d(5Q@*|<y
`N(e}k%&t1VUA>XGI#PqG18C}rAYR=r@R9sXdFL3<41X;>p|Mp7U=?CumU_x6tkp8R%^?J`pya>(
8%JsvG$P+nmD5Z;>y3WrGfzdd<pxH(5FgG4W92T8GaK_*xw%gHcwm2fxm^=w@Qa^5sKz)QDn<pPc
#F!0cA3~g7S+kBgDFx3MI%Az#!&92GlZ<Qb-c!s!k*GyCFj~IRFj!|en?EnzG_grp+Ln|!8vWnDY
T`6ovAeKZR(W_f_1mBP?L}PRPq3PP`P_=X=_8hbo}YSNyT<o%Lec-y8NV`%-v^$JnC2Ba;IeFS3P
ZMm|neW=n{jL<vH96&e7hMK1ZATb77;Bjj8tt7-E~{fekPaK)rnD20*H2wgJ-sRMl{n4`2C-OkKf
gaxD<JRK^0fm!Po9=)~hRuQsWl5^1*EN@%;WBzME*33I)s3)Q%!m<KTo6-N6u1d&|9eG1zxu9`+e
q=RSIU_~x!;)iB&5x7rN#ieFB>-_kfXe&QEdd3&J9or)BbE&&as%_(?FE$f6D~c>~8sB)R9mk8+g
sBoXR_@0z5Et1a7p&w&+dE{iB$_SF6PX;2BJ&vxvWgP>r|`)2Gk!Cux1EVQaM+tWpdjx$sI8X$cU
jnfKfhgN1T@=C*2>0voUb}DK(`wki98GV>88L)H*l(zY>yh+IxPIz=PPfmF|OPiSuvHkBRd3@ZkL
p;^qTT5$T<JR_%H2tkj^nUrg+>g)6z-ig!z-itb-$+aOg<bQAv)m=`aGs6&^fFj)vu2#;{#53iTI
c%%hyhFi0p~#sh6P+yn?Ur+h;nQ-@@B^6uMb`|)gX69*s8U%u?PDXY+ah~<{$^<|75Pw~qQg-Uis
hU4}nP&H`n6bB-=9O<ki!}?`@M`1sMGM&2`J~`5>&J1{MGsOdidJMh_4((u4cSft`4n<m2F86ly5
A10Fgyu2C7QT``1|fbErx|`UvMoHx(l0FIYi3b=R-SSgBURMSBbxicOgT^+e!F~&`nMnWs^j`~Cd
<h|KQxsi@|}4p|4e=XvH@a8<0fM)x8Hr46&hK6_ku*q>LAXa;Xi!ita&RqZUslJpvyniI|IAn7pE
W0Of;uO)|1E$w1TfU)fU^YOWw|nsf-$BX%V0~f04*|E^e3C@vgZ2gT09k`h@AUm!5t54t`hioI3b
j^VY%6BJ*z89Sjafj9bG#eijawzqG7EwvDjyT#^-g0;~1icklzhXxVs$`g*C<Ph~j|u*7};_@4!_
3~S$V^@-{rPp__ah50i@pxDa14f`36Ln2augcuR0AeY1m3?suh`AB-0?9iQWQ+yaR{;>ZDF!`_*3
~3msg?4Nn&XHFC4PQBR9&;TYvs+2(e4k|3l}fN{4xrL8?H~Lx6~73c!Cc-Z%lDL<)T#D0SL;>A#?
_t+PNsP_AR|`0>QSGo_Ptf#-sB}|aMH;D0cY2Ie83azdTYK%*uEj7UJjHuV=t!51dddvna4bULw_
@zhZSc17UgZH;_)T`zsv6kRyYi&*4JE%uA^~_Srui}&j2%@qk(i`S3Ex41mm}}IE$Ch^NjLPQyAv
~Qz?s-hX)78o1jg3O=QLcIFaL`$R{ZUNT8F~xfdc_WGi!2nH>yp4<8PK!`~IdG*u1)eLS|%%3Nhp
O*t`}oR#Rgdj+d9CR4{_^oNzY?t9<)%euY>hg>=g@tUL+kb^_vH^Gt&RYbxi;)zSLzGK%BY>8wm<
vj9)jzD&*pbpuM0y^RDqPm^|(@~-0!C@^pnw5j%63LSa7_kR%3lBl$GD)vCDiusim08eWZCLM9lj
=$BT3tbXpT}fL(FF7TS_j{KM_pJ@$MyvjxZW}}k#0$U#cRG{RJQJn=%tR(U~(NZ*y+OMV}_bFy6i
B?D|o$9lK3WCtyD)HJI8@`dTs?_4UZy5q}4pZXoVW3UAqb7hX7lEPWfC|l}B_BH^*^BFNEXJE~|&
5hPBiXjB4!F`T180d-lC`k83PV9p_ulevR~*$zW<|xLa$OE9nJ=Cl+h*XRu0tmdwLuM^28&czJ#6
gty<CEYb|uO&h85QQ7&Y*b|Q|nK){d%Iib-6POn_XbMbzvBw4=q^c)TN#8zNc(0n-mWom(K|<Mgd
5ysy|A(D$ku3AJCREI6s_|@K8;(f=ByH7<W?C!UjGS;}%ec_wX5*lA-?qh=KikXJRF&KptXjzpj(
I}6^|@;%%*|;ct+X>b-wfrK+1fhLK7ZOzJ$AgY0!|9>Z+U`J4<)JDB`>Ix#l}fqBg#V74WyN1Hrs
|wS#IdOSTB;3l!6*7Lj(;FPwty-?W&|W+o4_0m$R*H46nQcnAPAp&kkLKd=_X_+<tqk=`xv=IYq!
;dNS>7&mxMXOiSWuUm^KH4W?5pb$P@ZDl4N%HAkR?z_fx*NJbkFU919jGztPoVu#$WurC-fMhtq@
R!%6bGak1W7jyt1N$hkwvg<D3fK#fZxUgF?W%iT-sVJ}}AB!1=r2+CBFT_>?P3y3qzpwI=T_$3?F
*xYrHNPZ(D73k_O=x91!3)eJfGG}Q@@pz#lrmRr5%>`*wh<0iZUA(luLR0aLCHD)B7Gxo2q*1A%~
#%^KL9nt9CTcwhRNSAFZRBya)2L`wbeqFFXt1Gb*m`|1Sznvn6~3gd{&>71z<W2p=jiL&0z5)3b3
<DexK(b5w2vn=H_x7IMz=#<W$>LR#_+6d{Bs4ddP_iQ52}#zS58s^AF+_9^9CLLmA`l*$_1Q!HI0
IhT;jd!X+BUShMU>FJ6nAmL!S#U^xTntD9OLL-xFFY!hvd9@euIHkNm@E-L#b<&q>x7s+d*-o_5=
^jQ)3H@i19U%T3glf?}vV^w>_sM&-6%@%tVM;ymul~FB=B2Q~u-Dx&YQQWwShKh|yRV{EX;V2N3B
z>s%O+%tPXl$XD5_&l3^+$tdxS7ouRPqFS%#IH0guxk!diatI^;C#b-eC^_Dtjs+u57x<Y<c@B%5
Ocj;R|<vQwSqw+sR3B)8@q)0lj#j+#Xd#)rM%dQPeO!iIt7kf+tooE;<+Rla;87wjzG7IT);nzPZ
d4u|JziJM0mZ!23~5eZU1M)a^L`ND1ttP057qs(Ofx4bUw!Hj?FI8bVV`YWVe*)WsV4ZrDi~;&g@
vyVfJ<Z7fHM_6Np83r%3%lbN3C1lraM;4*;J6BTrxOA^Tw1~dZs^4GBn%R}i&=&iCM=KhT$ViTSj
m2oAYdF_DlJ0ChYs!oh*=<^m260;E^0(;{K*QwDL6d{+)3B(K$BwjQfiro|HGDinFZC=a4ve?YXZ
p>q-rbG~sJ?tn}CcY4Ui(1u|R8J(DG6%R!C&;~tu{L=JL$lu)3po}O3bk4t-wMdNArH`-Vtq1;=a
<u1Vq63i!9>}4av-+Dk?<6~s3Bnb<_Po6ex<VR{`+m-oFLQf?i;AKG$$xk=0Mu1>gkE~+S6zyE{B
RcEm!2iIO1mWF^{rGT#x(B!&S`@(`nKMcwtlt+HG6ly4E~QHR>Vf$r9p$8zEe~G_&_}wClh>*A~}
O{@M1pwYe%6OrN2bYaGFW#OublRd?Id4FRm<dfe+lC0<opR2!re<YMC7lCZ;K<AZ)t*sR*tB(7SU
zT;h3nwNM?D7#F_T%_W!HN{@5gRL4lu3pv?5KUF*pe$Zqtrj4yflu1HNYqfYq4H3hHltQq8#nuFU
?@x<_%?8HsuP)X)dqIg1sXInm2^>!#KIdJ#XAkOAsP$p_)9YcJtme_f@PZf48VAouX$uUH1t_Z`3
Kf#3+di)1+}3=6`O=Rt_CcT@6qnf-H;L)+mdjCAY`DmSV;C(k=b0r#8>s{sg9bWqfyx_Yuu_DjZ&
+jpPJ{u#;Ogl`dri0su#Z3Om%mY)hZoEFK}YD*iwPG_^KNcC*h0XoCS(LWoa+uY|Pc>4ADkYR%9$
~${hvsRZ*(Etjgt*@@7_ux@9a#;U3LOIc9`)^_2D6uUxQOR;&nf_zf`K%#mys&#l&pIk7sg9kFa!
|5)*<&jC{T{CPghmmg4@>_ou=2>>{AHj<s(<avQ5TGbYHqKF%`b_3YY%5*V{*OFG90!bCh9Uq=z(
10YKOY5C#bC`gf`aw-oiSTR7F>eNQiIQ4?*0wPQ4VW+D^g0uDQM|0KGU2;OUB9taGrML~OrL9B9K
YB2le*BL0{Ng?j7BII!6qyf#}tp(9^QmQy;_Ri>s7)*vtGT$1OEM6;oPesMQ-9LM-E5V&jo859&7
V$nyXSXEQD@V-qcw(39UhYM1z25%I2_0zKyP<2eTUn-_xlm4|FG049IX=dXyW8lp-i)O<-bW8h`>
;fkQN?SV|}*vz8E$5LJU$6zo`Xv{c*UuGmidF2__R=p6t4CSAf#FH}Z$ykEAi&+>{%x)s-@7E>fJ
vQ}h$uF(*zZyV$qVc#dPaA$vJTNFV{>8Z8gK^_^pc0?AUmHd(VEfE{L>za0rq~8<U+uPhYvvZW{*
jECV9Lv}?&fbC&I%6Oh)mUV#Zl(tgntLl4DH)4fGPAERi_z>yJZ&n38v%>><vDK^GhS~51O`f{0V
>+*u*%>0OKWGu8XfeOmu%z{PFiHw)BbAyezeb@t|MnIyV17Tov{HPO!&x&pFetwxy@U4{oc~3M8m
=jb_o}IbY;Hb{k)uQe6M*VZ<*gcI)u98gpnRe_2*|3{7O>S7RVPR#!{UUaiAC(wxK}XxbL0uWRaB
ELXFpL?Uk=Q@;TbE&ja87r$QKzV5|l~plvF@P(k1Dj;ZtTL81K#I9>;;7NMo6DtQ_<yy+~|eIWD9
M!WzH9XCdnrxmOgV~loja<NDD5^4%3>O-`(S(sqhv=+J*)8kGTMG7(}>O;dYm_82$!Px<ax(875@
(TpFRHsF9t5a1qet&hNv#uj^gA^$4)+e=nEek8IM5y9gWn{bO#b643!7bVTV@<bsMvw2`b<J8l?!
~96v(@AS<w5qKXu|ctIipD!)uyH4rDA6#{D_yAm9v8ErS~E~Q0zTY6R@K#mw%-2rziq;G*GBI*f_
8H+**2a&BDI_l5^HD2bSu0nZQ5~9*J3txKtMS#eMp7rqZBXh?<nfO;=Nn5+9>Nnfsfaf<$e&M;86
G)#@gtlLWlNs|&h*wyISEY*{yGhL&>-r48B`O;Gqm7K(yRAwjZ9`UZ^}-H0_y(HqoHvJACRpe9FY
oVVXj%cYId+YB};|NKcxG_1BL0F7dQSKx29h;6jovn^$1ViH?-bLBr{L3dr$Ke(_vtL?RR!bG~(f
vahNO#C>sxWpA)CfD&2-6@L(o@YTqd@XEw<GzIw8`kUJfe$V&WY_=3?Oah;Xbq>IwW~)KZPaN>f<
B+6g2huBezM+zaT}F%a0<dL)h&Pl?bJ~Qu^y4vOXV3m0O3K=)DODwnSS8gzp5YfTeCV!um1FoG>$
lW<lmaC)E6xKIqTwJQmfIv9iddMNe{Qy#A(-R;=^q<1sDS#e46SgU=4f#Y^=o|(>%-<KYe(_8bQ;
7dauG_94hr76z(-zZCfe?(-gajY#NNjq!{=%rV3c$6Yqcb*w!fv7N3ZqxILTA9qi0%vwm5K2-$e7
F?J<|vH90=;dSOu>>ae7Dt)a}FUK_ELGY;CrKQ|FU&;N=Ntz!xZB%Txn*sw%Mo|@|(%qZNCOsidp
8D)Y{bK_oig8sl9%hEqZ;~`}ni2D|ff|>I)7Pxj5DIQ0Z2ns0MjkY0r4s64b8`B_NseO63Fk;YZa
N&Xwa#=kUxd1cmXvCdJ62Ynm=s4fvqJSi=V#aVRNC$%wAV{Vm#x$fbdctXwTKhpw^|2!6?-$%Cs9
gzK58l3?vx&&3P9OsVxk41eH94^#>qOV7Prtcg1tTjipUt@$wk+oZj(sEnywbJ6t%6|G%5(`k}#c
8+DHn<jYDVKM=2xC&*IC3JabQip(vl-keSMGuNwSP>lGs_tC%!qjdZ@?EB;z2PTjF?cxW{`;-H#%
Q4=*x`_)@PgV4GgiwN%T^((&il8dmYPNiTe<_lKgs{utp8%Aw`UnwgZ;h*xgHLdADlMPiZYBDNQk
?=Cz!*I~+jvB24*@m@t{ZQAK2<_7Y2%ZML?uKS5qCZ>d&U0ia)J`%jw4sH_H47EBDkW%9rkrwvuZ
=iQ+<^>sG8#7OCCB%)bBS?5ijOL;nKDu;&_x9Xf?07m1SdL(EYoX_&|F&1A4SP29<FEkWjrfDfMi
@AkLk^LY=;m}3v`i-GqeiEw=G!cNj05tiRU{xu8jhJpl>IxOqb0a2ynzs9Iyi=JROtTaXe<kACJ-
d5eFpw73%_34`oPRk+>9lt-aZ&`_5v$H{kdMdl=o+1U^dhtQ9OswB|7Uv-EO~abQ1wSp-mX+L<7g
rmMiqHD|iwWy3O@stDnJN)Jy_rGuFw$Q4-!p$j_lI!ou|^DaxGf<#%-Fffz!aqyq%vw$K;VO(rwZ
kh$XK8N4q8)6O-0o%7olE9h|Og2IXi<H%77a3qyd2_Xz(L9A00a#C0<Q`^b{O~@>(irE8=i&8g2D
60W5kmuQV-Rt`ykvPB&*&Kt%QBXrG#L4UhJ8nlQ3RJ~X(`zaVb)Nl5YvouiKGbcR8e~m(Cr;j2oN
_i#T}i;u-6Lcw@9yH`GJ0CC5EbCD_xGgGZ!-@3>b;9qCU(hBx=P)_VV57tF!U@^Zz;n96abhK03b
0UY)-Nx%|WP@6h}IB76PAtMT*iPT#%9uaA!S!P|G|uTJ0nJpTUd^|v3s!&i^_#rw18Z(hG}U-b{a
zR2L~htp@@LuaQi&p!MNkB<&7vhRL)`4T$&>Dl=QEZKwR-@ZHh@b2skpT7V3)w4I>QxjeDf|`*EQ
2y2F`Rm&AUY~k|0n{F!et-V$>$4Zm^T)I@-@keOpC5jHdp16Q{Uelm!Is?S@sDTko}GR;e-#jWY@
SPt3@-Edhu6>Fyn;c$e^2jdzrKC*{`|xFo7dy_-@l=r!-FozM>)U{5l8SpMy7!8kKp+ceE%B0_b|
{#|7&#5KKtpzyVJ1@JG5i2^ysHgKL_-4NI#G0=ZJnD(+@=lsUBxvxA3RemH&J4e_#GTkpB<m|3~u
w5&mz*U>RSo(%E#p$cq&B(HQxdP*FbRwU2S`zQPGv?)oO$Qjh2AQ2gW;@8j_-an34w@uU`zfehb`
AAlBMr1-&6LwS1t@L|w*JM!F*s2aV;mCy>qluWbeBQ`g}uwlL6$rG+pNg)F4SE3^qIQa4G^gV7#K
RCJUWEK}i@ck!_4jG=2*AWyl?(Rilm&6D#PV}2s@1M0fz_9qEq8-LYx&vg1Pl~HFOPmbXCYIHBoM
ve`9*5}N?#BIP^QqZYC(RZsl^U(`3a09=96f~*0VuAnlBNG;F{ao^mg@x$1?|-+$_b6765>Jk_Jr
Mr^tfs%Dajo~y&bB0qpHEWG*=g%Rmf=Di-FR<Bru-@!(F5pwgp{?<sf7uuDd+=lq_=<IGmNAupk}
(JlfTHpizIn7Tq)j-a#V`aUgj5@rsBBBJ!+>J1xbO*wCh6h#WAY3hv9Uf}vRwJE~%D<7*uogZ9yJ
6#N4k+=L)u_0c~9QuSi>@PKyr5yq}{kSB`V&}WTEw$JC3nRt>FXgtdJo?$_I?wpmd(#8`mH}K$)1
;)tkWsxKwoBBY$nu1k%v=nBkDo?6Fdiqp=!_B)(OL<osdiU&5Ga?K#+h>lowk%Hs3_Ak8eZs}7NV
joZvN&o^>fNovI09?+tt<phy82F_cUwdK8<<qFp37)%nnq%?Ja(6BG!wh&@X=w0cGKYjxJh5J^iw
RJ!Ka$*(DWXUCWGy&jf$rVAtu_7`>blAji*nW>|Uq`ze3DQWDqoSI7Z+Egd+yt;YqVx`3(l}^ugg
nKQ)Z`D|Ri0Bwf$YX!8SXVCp@h6KUz6078#4nKQtnf5}YTHBCp}q0n#}R<hx$%|_3g4oqVRbw_m^
g{Kad#&`bH&?X2D1vbpXcRcSw<2g^mZ`y=23Xi~SUq~f^EviTa)$Qjpiy<>nLN4~XJ7glO)%e8;7
pT5t8mXv=yF2HL678pS8Ur;?;=pPkW4;HSSjQ+gPm{4+QUX&&7)&x=hnq9mA7&J_kA+;aLI^+vod
Gr_Zp2bDg^`(<X<6@NCT3dZ9rvML&TJ!J1yciHi^;AsUi5xE$AGXxO)4GXzLeKiSvW?V>qFAdL&<
D4cX)iB0$RL!@{!@D(1mI4k>B*6CrkK`iQ%N9&-S^WCGiys0J+C`N4Os~TkkNi%u@>rP2|K$mEkj
N7@KLU4x>ivLZm7<atboGZn)T`snwZMy?8?9UAZbJR-$n}PTb^*TfMz<&`!&0r8*Ni>u~K(gaNRd
BT@u!FY}q&&~zwNkPS1R@=NA2s;})PiQj+144engtFJ5!rw!11v=y^8TDJm6x$%DpqAOfI`Dc;U>
==UbksqBgcBhNc2&{Jfn5fMbT9+ew;{m;Wpvud8t>tpsGL2nJS%r`r`i&*Jzrs;Okc|dNF=D~a)7
ounW*^1&F4|HQ2eNx{MPsbVHdnDB(riQ|=wr9v3_jfSf@opy5ugvE6^U!T4e)Cqe4mS9o0nh*BE0
eZXePtbZ;ce!coTTKzD&l%z|{B@A8%8!)M6f+xSXgSgaG5&&){t9(te(?e;xA`!-2({jQn1f754c
uo(7tQCjO(!H#-AX2aMuEUl6Oc9BkA!wM5Z9MjF$S$dF^EpH-n5rVj}9<ixImU;DjndXp7Ma|^j6
;mQH08;U&gD@+BoZ&iCUdM`aoxLrDCtigB-JAqHDjWo0mc$9f`XLO;m@ulavL~*UZ(5$Be^s3;Zl
|f6b_gVG>XQR?XzRMZYg-8u~8MfqR2a=FPGW6&Mse~Sv|20N2#3ia;0MxXWB_^rBTPj|xuD1XgFD
FeyhVyUC@I$O{?*oQ57PbL1i6|aawQ)chFmc0)63W8*l}Rh8-Ii4G0%2BZ$6WR7qY56xt78yoYWF
LVch$$9#_G30#28g?W~vRwv-CP62&%?l9JPBJM?-}PLdQz~Nw@N__3vB3ZDq&bE1HibqHUWTsg07
S(AQA~!Yw?+3mY8X<0)`kBjWcsZ#CTiiI>0WWS*2a`P7;L-5ie9*l6^h{%xbb<uC*^gLd%A=@sux
s;Zt_I$0m@pccbcWmU*|xuxzYfucLQc06D14YSzqMn3hZU_YHd1Z_=ZRU$+G0jKKu4?6EbB~@yxt
U6UYh}0Vx8i;(e+4=-tUF@+yQr#o2NPbU22A4%y)fnI7#RPz;GSW}ADLaZsHP5<D+b0T$_SkbuuY
FK7A>KELsOu)C>0ULd_oc?^YLIEVnd8A7?>4wcIJkcI-#xmocN<-=0d$}Ge`w_#Wwn<^^rL?XByO
Xfyu>z-%`>zuT^i~kdNpD~gn&p8dd<`kzf;r7p<Db<Dscsyj0{wMV9M!1wiYdRVdq{jP6C_waEO5
^5zCIvkN@=gnfM!%_Ku<wlc9##c&L!lWTC=AG|8JC27wHL8^%nJf-@Ge0Sm@Ej4|IS698kf(Guen
j6#e<6ZRp_EZ=l2@tw_C7g`Gd1pQT><=?`<zN8CdVWZ#k2#O^6=yBjDBPn74dHfV(;69#|v$Z(?l
l53lZCPV_>si!XUeRVL_wAMSE2!<1iX5HZ!i5?FNl8YZ+`ZgoV_d^Y8=EV6t21O!Rs-iPx^<ZXjk
j)kgpL-<W%;WNe6^fg#136I9V-q!tO1dSMk&@UBcFYn$;MJOt#5LScP$QFOnrA2=3<kF@x%<tAIz
@G)ernPI5mP=FZQcDXy<0<FU=QIzSfT#oN9jEv8-P-2vgE$9N{I@uML%4`KGE&B{ELZnKWsZp&pU
K+E9N{S=sG}ZD*G~u^RTdKH9xDwo)A{;oG>(r@5+S$(H+eqwSht>bsb<+I#9<P&MzG5V&Feuj*o-
E%!MlTL{CjE=2yduE?#eETfFNZfiiWx&T^1w}a?kg2l(%$D?U8qw#SA7H^QlYmHUWWy6wSxb&KJT
`Q;?;%)Kw+_==z?6#<HaOizBeAIEYg9E26!jhQsakTr|`Y5Jq%P+d@bZw2|jFPJTdN;ov3JGsYoZ
)0|kB<IGO-h4i>ldoZkj-)XG%U2twHq+JfWS6(fP%sxTg)4F@6V1$n~s=`3Zc!x`f9+Fox_0l>Ql
BYg)Mg0mBmq0RKU-nliO(F=fObtj620L?AsCGR80(RdRq~-+KG>)@K*5JBG!yHG#gcfzEhzpr1kp
I)}7U*z>{T%Lkn^i#MRZXOIaKNVaRB6hrQkNw{ti+{=9bj{&tQrl;aK!ZHYhW-Mwt*k2q<CRd=pr
KsXtrzU#z$IC&WfUFWIAcQoC*oAymvj~SEUU)m?SQUfbkJwTlr+gP7J=g_oI@8;1O{>+qrx^ZukH
%h|hty?r8iqdW-%1(n%%%QS1egm?b!z$}Z*{7`*cOWwMjmq{g3C^N!DcgK+?}a8bsAs>aN;$bPES
=NBUjvUf#}??@t)2Ml54N&4wX=!Nqd&sf$Ux-28S`nQPZ9=-z}twl2&m<al&l7${mocvjXT;A>d>
P0s%c_`3B6{N_{UkIr%&x0ARjQP()I(AN2KrW<Unbz!)$;w-rME$UG`eFE55FJ)cY5XuD{dh`Wr^
q|FcI|Y>Vw-TuAgHqOJ51Um6%cpCP^)Z5bYlYL4#+*8)+y-(+0fWd1_K!jTvy!apZNxeW&ggPp>v
@tiPzN>~w{xS@7%5Yg>u^f?oB8s4<YMOgZ*#t9{PbUO$L8-~JD{H(qWJGRqqt6sl%cPWnBX8u|GW
WI^msdK<NPF=eB)K-;#uBb;XA#croO`=RiZ^#D5QTv-<jM|eeN~)?t#vb<$2dIGPX|0#-ho`Rr{`
N->P==DUcA2a(8aQ7~Y&|r8)zg;h?azRjOy<|mTH~E(AiDBxGbomm;KWhKx101_&X}JB=`KVM8MI
%wmt%hV*DZXshnGb}9q9=SVK$@P>Jx@<XI*VD?OyuV9T;5${4JD+VUz9%n|}r_p8=EI;gN2E#SVM
|gNa7hcDCF9F95g6>erI1cB8&N>CLUVRpQ^EM)*_IW_;JW>*3>@&}P}aqR>`_qm6;?7#V0}`$1Kk
z2%m}f?d}Kvqt>?W6B>}m-D0%^@$-k3EG=sg?GGI@Tpfv^ErAeIik>2ES9tZjb~GnJ_u`jVwu)Zp
k2Fs17>vNeP3<3Y!ji*Qroa0p!{Hk2lx$&TR-{PuB&Zm?yo`b(Z=>HPgP&t+OV${_1nry2}%R2;p
ZQwtK`;#Q{`INy_!{*<`i~=gW(jucsu4+emJ-)Eb@G{7{KuNq1wowQ!L3);eJK7q@K+;_3z2aYRO
gs&Sh_nkeIt}&s04@4(U9a!hB_9O|Fj6pv-pKaQJM>+k)ZT3C{Ot#~XI2%yIKsv{@S$Ulw=}dlca
GTg_oGMRTxGWNX7)K|#``oiWohk+zKT$%*dliH7?|e;D+aQdQb&vS`dN&z>S8lAb|5*$<kRu7ZSW
N^}~|I%O{NKK$G%(mEbCcrfV&demf~AYlQlt+A8Anp4@gliVtJaLqZu9nZ4`r79DGcSA9z87QNg{
eV=<rnliB8`Y|fWs;f4(p6dW)ZQAyqc*+s)U{17nyHsXhUz=Pceb3IY!TKrdmPx!+KvZ1wOaL5Xt
2fdXkO}^1eK&iq0HrcbIxP0^%e)XF-B!<=~RR|CY71PN%y|jg@2I~Z-ve7s-}s>AP6gVjpRuZ1&c
UcQf@hMCbli@R06(bB~x^5u30XH^aRVi<h&27c}NtT?jc*$DTS1y;*qkWBU3>rE=GglB_)QjXG=G
t%t40~@2$msM0U(eV@?*Cs6Tq%Zr>Ffz5Nq4jE-Xy>eO~4>ug@RkllnFCza~@9b3zXw%wMF;IBdG
stg>1pxO#p-a#r&WE?Co3^|1zyECcWW$+5pjx$pOpk41K+c?rPHnq(pr6j-QSa8eqdd#6qt%z{%(
rcAK7&#h~D6|ORSj^epG@j+b^RuA%n9Pzg=hVF~-v;q=&OzYbtumbg^w}(-oO9tXzg)`4b{nluua
}hQyWL)_%bT3y@9E*dQ;aeA%P&!fL&{-L91PHBV#VP=a*Rf#Mgt5V(2JnBNf#1at@m~N5;NgJ&*`
Gu`{kF53_b{>h6N5Ds{({szx=```Rzrr#5jvIpWtnd`O(Pq6*GS?N(sp`zsM+MF=o|;7BtYX70#4
AkCB^R2WR}M&4KUEVUFKm(7}1Kyq2VGDaGf$PV#wDq9yPZ+R>&&rYM;)j+*j0XY?53s^Sj8aJn~?
_c&jE<Opz_`U@l7bqL(}H0WGi-qTxz)t77#-T8H1Q0P#O^hxXXTGD_~v_uM=7zck}ft-(#^nzC@r
%hW>k_JGygrfxB-NYqkAv5{Mcqw4}<q0GH1f`gPBxWuW%Gk+)TsbZvrLLh>jXx$CH%s~GRMgim3s
^hKBFb@GF|dMUf=0AYG6{f3#2uI$yg{Qvsmjqx6a1kt`2{pKUN+-kyUqQX9no$h8lq@dlu&tclO|
VsBQVHqtLS074IIYB9{eI~k^&=qfh!1&T_;oen&oX+CiM|khd<&e{rdFP*~pIHm(D4CAqCr2UqIN
r(O)p2fqX31g;nKpvA)O%zE~bpO%#E=`Z1Z5ImwzFr;7IqhD}@naF!f)k#^fE!yrZ=Ty*&(N99M{
O@gr7=^k_skApec!D9^SFEGkx9P~QJ2k`VNy<U+aJ+1zcY62E|#sP!z8>Kda1wpr$E-c-5r{BLB|
M2?!!~5~uvv=cH=;Vf%XkF+nco-aXphq70-^d&1l1KxP|9r^^+QN;fXc29CN(&MEfPp5jBs(7Fv?
GIf+-cD3i?f$+-n|+>d-M8?;_j(aoybYBNM^Tb!MRlUNwG+?r1qd^Kgkl*0hsTcucYO+JPRhX_%@
x)oW^FsY5|l9@W_1%qfcrNac|YyU3%MHdfQ$4+FknFogsO=zHvt|iDy^Uf##)WOtrepTHU3oYn|+
v%SD?4!WZ&MSr;ArI8+}x7$zEX%eLDXWqLp84Mupf^8@m0mXa(P4M!@B9>rY6SllKu_Qjs21Ux+0
zdGX>ZFBn@MR^@?sq19w2>}l^F7L4nic47KSMEoBRmu6VMTx^r(=q(D=zHlQN3_GKIDyDGJs<&v%
DEw>?j*W0K}aUrBIwZE_#@7XKhd1{BM+{sLS(oNvDsmNFd8{sQ~ZI7V8G8Qh^C`b<#C^IS410iXx
mC(0>x3?_15X2x48obeM1NI^0PXq38B?u%F&;?Fh~u@9j3J|th_cV^6?N>WTe75t1_l0g{2)AlO!
{tH-X%D@<q|PoAYHi2FuTvYxKdwEKdcdp=7I2C9&(xMWOO3nXzO%x{EWwd(v+gCy0@*m~%=MBp+#
h`74|z$mqtJZ$pI%^D`jjFY$z?vHIj2><}Z7Q<hLSjS}T#tOv1D+m=ocoHcUMomqMbbS+Ja4oVC%
k6D_1JmLI@=*JbR<Vq6zePD-(!6zM_464S4I_;{-M1+-95g9~0opOBik&$`01S=rO4%u$nb@z3O7
QW>2brlujv$a0N3|Z}T=vD&334PlIw>FHhr2LcjWrx>mlFw!dg-ce$?;uD+t2;}kCRnJ%3-uzhd{
oLHAF&?e81reMnpnC~OXC6OHaK?FtqkDlyH}?let36Q+w3wFtCllFPGHDPM*E-sr<vtK%~|uh%z>
I5h3+;xqx~hP6DLXLR7io9A_1P5bP{zf0&TD6^puVH9AtNH*^x-WNCDxtf`by;Wu~@yA5-cG-n4L
teoo>DJDCP0k)Zw0#k3+~l~p&XNj6}{&H>-`$vAW(p6~*kxQPxVVIpM%{LM<Zf~g)VMXUKg1;Q+n
sRVnl)P*!h;IAbft?yb2FW0=n&;*<Zi&;ELpofPzFDP0hi%L>}%1UFa^=MWAMxB+BC)c9>Ra=Y?5
72=X69$;2VcF^?zD)up`r5LSN-2OHM4WM9)2irng@Q>`&yW-rawx;7jj)#}BJgcS8R~OG5ge6G;5
EoE00IOwhJVChy@=4%B#5>7_y&eG#=!BMy@NBcqvD_tVHh(FsMf6P?<k4K_X&9+ueG0T%nb;y3Cn
)B%u7;v%saJn9W#OONJ2biadIcTXH4SMpAkkd(Yts#wVtV+0GtETgP~1SJw&z&p6Xd8#|wj0b`@q
}C12WYjq@NHsrIY0_ul~rW@8jj8mQm{IK&^gxjF!McF6#3C&DBYh1D$!osa_;iD!(@(+N7(s)QUk
W}ckR`bpnS_C>)%E@Ti9I~()EkpHxZo3ONwL;~nlozXFQbR}tr8pKn_SXUtkLld?(9@%4%Z^M|5Z
a{z+XYbFxKYRYcAwZs$sf|QvnO-Gn9CuLV+Q()dZqwv$Jd4+G7Adv?hjNRXkGmLlM~xGpC9+yJc(
qd>8XJM@n$|ny=N-v(OoEO5oMu^jsn-|FnDuq2fz9zK4s*<@#wy&it!YI~7^Zk;l}f>fp_A?T8>1
IQ7V#4nCOwLdU2sk<T_Htkf8rL_KoRVU__7Gv_x$z~yzK<<b3?n3ltJs<UU=UM))?9$Xg>|YPZYR
e9Z`q^;DSM5M;F7~(hu>CcbVr?q?M#zndSMiW6xS{3M^a#j&GUXk3lw@;W{<F>YQWlr?gz_z%O&A
VRi+>!p%8t2w+QyJ2|-rjOoA}%$Ixn%bK@2KTumh(}0n?Pvc6aB}NNHsP5RP6t5Bqro;Y-uRsXE*
mP{=R$|N``^x*x<uU9#H7?0sZ~;(7<)B#bRp3*cMZrVrfD5&PUeZ=}81r;Gz9;Ks95BY<rOxe+_j
z!>ci3>h(=|=4O;f!MP4%`kWfr4l0P!hZgwDFOR9$N^^qS&81fpHEkEe-703d=~E0A|R^=@t6HQb
Dw^-)Wqt5_)6SuHSYaOm<v1#0+9-Z2k4y(@d$kRmkX1%1#txT>9N7KS4+s*sh2HE+qtqCZcBX_K0
ijp9UXgR=>afopVNDMBT_Rc}K{C#zMkL{4rf5i};dk0?!`)C`D*I--ke9TjuG8|<LwteQ-+Nek@C
g!rhVgm+uNTMIhH{S0-55#=JlZ#U$tn*%&4O>>B;<MBC;-+AteO{&QO@_=zLO|K{q1TuWs{#0Kh3
^47GC{ix<asPQ!{j=wwL$Pp^=D4F>pcWmZ3rT=Qk6VGYuu4xm%h}fuo?(o7)PM8VVE?M(@2D}vLL
L2N1qb5PW_qOH6C_<<*LfuFU0RPiwtXloz=XnfJKYwM<{o~i)SBjHNaH|Kr2DMEL)Re`27<=Z`%3
zWOy>$-xMy6hKrJMS?N_rEW(Fxv`juTHa1HKgljAj9d>v!DG3SCX4}h(i%|!hJBAMco@PbgY2G0<
KV7#T(8fIK8)Ip8ce6ysD_qS8kBIcfQ?}K4cgf<pA-;V;?7J)(mq-_)lX=-*nhFfAx!Rz4?W5MA4
9i~a6FzVb~Cbx;p{I1|@y=!3MSSF&}ggop*w#agod6)`|P&AMw>5SqwodlToK2(L|9bQo{h}2{hO
v)y`e6ozWNGD6~LM(GaoV=qUqz-;pu;0emR1Z9(+%i0kKJn~aNrZ<d(*FN62cH#wX+oEHCn|foOD
yDc++`<=yiz$A)tp;3a;~7-VZ~Nd%}e_+S)a_}`Q<bw+m`|ThGRM!4$O`i*=cmnNel-JCDK6mcKH
=%BS>P5yTvqen#0zPaqJ3Tiq(9M$PSp<v$E-^*T^3740?2{h$KRRfw-hYIN>q(0L|6B(Yjy)ur*N
I<c2#@MmO>em9gA836Z@{*QND5np)usoo5{6WbvJNIt_=i`h4A^8+gbALXr2~+1u|=pPyL<y*839
;w5`+tG&|5r*p}1%Ijg(aJhAQk2t3|qa04Zl<bR~M&+@!pFlEFW5Bf7>jgd1D%?tYBK6fq&TJR4E
37X-zH7?2#GJgc&Q+moO?x-`Q<)}Uo5b==4us^M6jQ&#&S*FmY<(4zII(#V1(LDi2sj5drTCn#`C
dEEXPxBU<)RePGn~OT)?%cNJrZYr)Aa_-Hpprd<FKtMVcTYuOAN+vvG>gvUwjdKcXs;X>|FpKSu1
ng?{@hUz5em+-TU)5ug&|%*2~v#UYxz>SC%%H(7&aJl4L88)sY$Z49dwn_rGhqy5Gc&ApWoLf@JH
61xecndPu!quhmuQJ@oQWiL)%Ha0x2G2tx=t<$v#d?ze&KM;-#$>-Em;?Ck8!Z+2DuiA@qfCNlX>
!Af4ONhwaz;|nJSc+VSr1?HBc9ngT7#QZ~OE$FrFe6w0Kp3{R^roL8MMt~6ai|;-k|Hl#@Y}=(B=
=g!f9foI`4ulD;_i=Shp9lGT4m3EDf`#bwAfM0jxi^kr>hV{$%V8A1`~Cf!YrpFrkn}~ptc;XmQg
fk~#d_!5X>(Q2TG!wG8Alqh@4BGPj*L(qwkIQjvf~zEu{JMJS5NJ`tY6aapYPSR=u_0m4iNF1_ir
6R{u+~kCIQ2;FZ7c|cg*+fFsGlPVd2>`FY2oP^|y}{E@b0t1v*A_4z0{!@NaNF<ra#+n*cN>)N6*
Cq8GkyqFA9mTaplP0T>%sPghxPO&l(AuE|vXTLVie_@S3Yww5zgrB$Z9+i)SupQXb`g|5Z3mtw^;
xogE`8Tam9oH>phO!*G|FOR3hdSW5%66+U6no|$ncV3YXj#ayv6YUHwn2s;YDA1+!1Qv}$=9Cv_O
c2<FWw;Y1&eK{R&xE<`sLRBtXw|1zp~~r~bi-a!*^noWA*e#RGU6+v9L;R|xKr0CVf#sKur!ofB1
13G8pBf>edcNXlyWCoE!0_t3Yot=4^+6G%(sL27Ao~{_8XchZ)nyvawOY{Cr9SV(TOLOTgFsXrpX
1jqsY&naQPOyM~(rg^WQ(`9Pb1ovZHO#DQrL~8{WW#>ip8-EbRBh?h%=b3y2G-w>Y>hPN0Iq&M$`
a*V8YKg&xfpH!yd8_~klb`K+7e;f_P@5qIQX>qYFFwOIqp{Q@t7VLzj=S9DZ7J%YpS>U1m`8U!n&
)qLX}1m@Io5$~-T4+<9hS!}K|(g$mr^8aC3>U74_`*{iMQCuskn5p=GYbS`D{|3)saLfyofp;H%;
@;1@a1;9gH&M5LE*5kR6BRHLEEZrFmVz%7ge-^GenKEJ+cnf6bmPla&&ka(Yl_WETy=mw2$MaAYR
`?(p7^63n!9H2|DY-zEM^UeD>lr|H3++g4qt8==GbNdQig9%1t?mkP%?}tM-SHuRWT#*!Fu{k`2S
RX(xq98S-hWITHI9@t>!}b!j|NUniWs`B*a`fRrxe&iHH{H>icFnL$tkJeq%>>ygR0d>*3&Jf5Wo
uFVl_HXxHee#hl#`98ve3tUy?6X{p1q5miw}2xHa8ie+*k1cVnbX11aP@FCkE_MJ{5xR-5}fLcnQ
?Q}IEKSo}Nw=rw4jDx2w@Z8E7(Br&}@VsEd5W=Tw{<1JoUI5(qSr}ydBe>_nWMg3b*(7$%6`i(4w
Q<+t{w!mytM1|M_`n(V^C2GSwrMzhKmkA)B(BLLz2__x$`$Fg_stG$?OR<((8Y-ZhOp=@_Lm^zBb
L>-1lGzt2-ZTN+>8#VRWN*dMHuNUh4KQUeVfdm6G3dDNen2b_k^d3bAvOtje$w-oc2oA((Dj*w@I
FfFn>lKGrSE`px1QrF3OE5lU!PnWO#ZK3fIj{1HcG@RWZL4yrc&4b#0Hs&bAVEF{zwGgndoH00rr
_N|Eas790gbv7iXSC@6xDND2y()T;vzns(c)*Z2jR+3dk)`{vu;g8@8neGiiKgppa!QbJS%Nh7EP
`h~j>wtj9?Z-;p%t2xeYE}VF|6gWWrlsQO*LjqM4EKw6sq|Vt5=BRqN+)luT%!A-3G>w{!3Prd~$
#BxL*TjU-6jSYv{GtQt`^6>9f&+rSkoNItrz3C>yocRC(7MA-ZjJoNmshSJQOAx-5AP$$ofLe^sx
y`@a?sH06VOVk=%mr=qj>nC0i`gx2U=h(PwxeBB|ESpa3nur$DhOmgv7;4o*ReMyFe?(uWJpIR#v
58y|JbT3y{W0C9RW`v^)Y9w)Nw@s@n?99Yhvdc%glrXYt_!Gu1<0nOLnHA-2VFV999L%LRJ4V{<W
qq>a@|o_iVs0fvSpoYfJ?g5!@5ySCe&JjwHZThQBpGe}>Ev$ZA(WwL~m$3Fz~r9~&PHG{FCju$%@
&gTbTLMnv8oJ;`pX6ao<NYc*XE3r)Zn&=`-abdcURh(J{Lvnej2oh6CwZO!mfBd8R`1Z{;ZgF{?N
Y^q8IL?9j;zptd2Bi9ur}U>Thy3PxV1gkpF&22dB?@>|G4{2hAy`!=V*xYPz+l^Eyb{55?w7v-C*
V{P
