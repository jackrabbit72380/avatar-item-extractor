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
Epr@w~pWs$U=|(k@&DO#Bi+>=4Mpjb{EP6~Pkd*KqDd$qya}laAPm3PPES<yder-}C<O>PA_nIl1
DwySMA~D)_fHM!}7zqfUt8xrD4Hh8}bhZeov!WYN{B(v>Kmv<zh$y+Wr|D8!HT%^)<AUql0($*Si
&VOLEh{iw^-;_Q0Cc~dB}!p~`wHPO5HXd4CA4INw}R^=$CQd|yFps01pwc+NnhY$P9i%KYF!8kC5
Tse?~iZrS*<Y_U+A1?K^JC(oG)c!T!G}$B|6N<7-LZjh$im=gg-iDqDj6w>QtFS^#smQx-1Odv4W
tGSc<_x=Xk#pyheJLE~jm%SguKIgRM@xUgyk{xYSCup&#7D#my|e)ZfVlMt#W({c&lk6gR6fotdu
`tHpd>n@XRk<%{h6^^3EgDC<h~AjQF*e>i(JKKtpz+3WY`Z(hGg+meetJR!x@L39}r+5w)LGlJrG
q{L&Pmjz%SCF^0*jq8^&vnSyACb+wQi@_IZ*I`=<PIxQv?GNWKcnN`xpsX7lbh1PaSKoz@Xe*&AF
9D60E7&u5hx`1^>kp^rug~6%U!8t?{+yx+sw_h-3_A}60{Qs;`HyGv@$LD$_cXEh|9Sp)3>yh2{~
HQS(`2leL;}KiyjV}r_#e4qg35JT@~2x68<c;VCTev(&&A&V_wMZZ&(FU<>pVMu&Ba+t3x3RJ=w*
DKao`I~bhr2WMfU3Sr}2xkw;#TPK^-{8X1Mo5#e|H32zago&IRF!HKrOJjBTp8Tk*qX3WQ9e#iB7
~_#*~q#=1))Cn!s-%7wZ;cH7WL7gyq#U9jFJ#wzq0u&Fgcw+VP;X-A0n!qjKF6(>3<<%+DE(UmvR
CYv;83`%S2LcU_xMu)&!ssZT-<^pdFD?Ry*psg_XRv(^taBOSRSVk<08BxxbOWd;sKJ|HYs<AHe1
?9W;=hSn}s~iBZ+5uG~GZHFr1M@5}EAWG2n_sn(o*BF_N*$A=)^ld|TxAU8aK!Y!b`k=0UuBkvf`
PvHY>ESWaA;nKHUW$+#R|p7B6v<r(T6<8Kum;ZBoC-lx}(+Je}XNw78y*$VLIQ($Ym5^#VClc-6R
+=&ZkwE>rBXCkrjnwQQHrN5{nv8KLKw(5VI$D(@^<#d=Y$15;nDABOY}24vDh=H#P@d1ItIp?Q{u
T)pR9(eT7`tAftnB397jmk7LYy6VH&dSrbQur?Z?1Py=^@_S`3Jhp|j5(MhqqOBJ_UBuQ3Ln9@v9
V8U717F_teP7UyJRMW+&QfUFJ&1D8v54>s|L{#%+>yZ0_j_53v0d;_RS(XI?F60;c*hi5p*vWvOk
s(ErZSM+8X_o^t0hNd-NiuUOlNMur$cJ@1W{S^sMGP9t*mTyf`4qXkL6(h`Bv-~$mCOh&$+Z$HO9
8I{T)>Me?seE3*@m4JHl=QAhXa$VW`}0hFSNAD<qhE6ta_^^&G9?7vOJ^_RJaV4wTh_doA*RP>!Y
H;X%29i@eG;oZ?WRRvV>)34QUU)*fdQ=-~or6HFJ(5)eY%-Bj<*Idp2W3QBy`&5SA3a)RrQz01*|
X5mN(_Em6Nxu!PhJo*|(Xdpt^Ji}H)J^h}C(+l~LkKBKhUWUAV<ojZW9a0Z03!#bqESKnME_++(2
a?}DUyewq($ZDtP+{Lqx-XUSp;Q+0+3p($@DK$lE8hp3q<WnKgZJGcaDB&=`Z>sE<H5XespVic5=
o=@C=0h4>^_arc($kYb^QJxndOh1=-6qK3zXqhU0o-c@6uOkhG8d0_>2H;#e_tgP#8R9ewdx`ky%
HdD-KuFCJ=E^AhD(zz$nXEG10K(K_A)0+eJctYUo-L!boXXDC9e`ZNw0JC>_fw^DgC9L&zwwE{L|
(><o{d7mu<j-cu8Jw6O>9ai3UKrNEFi8a7VgXWAIj#{aX^+NSl4@XJnoqJg2rq1&?C67)WA^Ulz6
V!YHU!c21?-K;aGZuHRx@w~t78t>M6IzmZ`}bOP1DFU$wxl`Dp_`9<kB570n8E68en|0*Hlb=*?D
hkbg(KF@gdZuvah6s#gKI24x%xr)&z?v}<4#B(b7%`D&<o-AkpjzJJ&RFeA-FT`>*wm>xYo@}U}z
%gJUMFo^m1|PokwX7Mt=ro#8A7iN=4t$Z<eQ}-<aay=Q6@=sq_OhT5%lxUQKlSyeYFKB#G-TFaWz
3=e9M@%i7{F?dDQ&&vW0FDjs#1*{?Bo(%J=-_WSr&VUb0=4w%C6-8oy&HiBT~~G$#|79Hq}FHa-2
>p9GPcF!W!T5!L(tYIfpTayh0^=hdzdYkN+zicH3Xa?W@!F%h7MgzejDvM>Pm%=oG7xjkuQiY7zD
#S^zPhhnC4KmrcOb>|n3Xl1UlziQr*2B!F42^|(aEj0StaX|<cEo(R;=G|f)5^bv-uz{99A9)-pn
i?7D3st0&%l2Sx!M}XQj=544}u+_M<EghH$VJ(e~tgGQo$_Fm4Xiqi$hVDD8Z%E>Bg*~y(8tK17J
Y87RVF)x$23*xcy@M^W7rfI@U`N|A)<`;*CiPuYHG+`|LE|VkBFm^&r_Ne7^U!KI%tP<QZ?-HgrU
z-N_I?#Gatl=q!KW^IG=p@*__vT8wz9iS6rbkXoTs=4+jQ2%6A6EL1!pSiO$24(fSb*NYoJ2Gs%R
4U8uyzF?qaV;>|x8bK2p`MlM=0KRQ-Q)hv+_`FJ+cs@nOmktG+puVp7HQSk1$pgN1eU^Jae76#?A
^)Z=AFn#M^(`SaLO%>r_Rf8%wgOLUl}+@h;6lN5|9v+X-LOp$Hky+X^ni|qBA598AxPd}W#qss|C
WmzX@t{JpuM;--i?Gd242QZdd$@lNG1g(+L|0B*wInv>a7rM2`jNOUcI)I$R=<1Gis%#s`T7vK0-
+y@do?wf17j$#+AuVTQmn#UO0yb!~3g#~5!h<a};FzXbgP_xaq0vbOAi&0*ON(tc6<Geo`TMuupZ
-i%XlSN&f7t7hvaHwVKyw_}1G8)^hWdvOFWbGNXJ^dL(@><b59c4gKQm4Bj=t`(=FL}K>U?*0`r-
^1t=hsq)iT5cc-Y?2WkOjzD-`7Q58t;j>K1uoO?3|v5iDlg|H{!lHAZOw>sdmN_Jf`{22sLMQX|H
9LwGgd*ZmQO(81)x7x&#R|FT^*snki(ceWKaf%QinHv9^iA;%;X5^m9O;~i$DEmewO*|<bN`;=&E
5wz1W;$(4?-w{$V=9s|wNF2=OQso`s{Bt@lii36H=)A0jj&@UZIZ^7d#o^#^q?HpI(KjZ-$d@KyO
Aywuy;a4y$~lf$fIUa3q>zRfCo2=Cg@G9>1f}6}g@IFVR2PM)?x69)rR2?3o1f0?T$ESE7!L$sZY
4P&-R&239Fdj&k}v5n0U$0E2)Fs_`i4wz*cpdZYtjnku3B(#A6YoGpTL`DE`fP-Sb>YTf%F8Z4zT
O=6sgWbq&HD#Lp~FrIo<B2m1LTz<3RfoiafQFiFEG|4!eeB7MI!3Ze^c?|6=^D|E5opTO9ZmqFe`
$zt%&ghx@^C@YIZY(`fbC?M;00of)Szd|-ykLRBpb7$ql>(vJpeJier0!hQ-HwG32bWuV2)AXam~
5-cC*S0P=!+tbARdTZIqu<tUt!Wh<)Qs;4(Qvix-R?MNP^>D~M%x;g=JaogKt>%}>k}Q&n9N?BLI
Nl_ZD>M(`F3}REQ%~E-u7f;a^Wot`nDgl=W;c-i0G|j7T{U6ZHBLT4E4GP_3B*2_^`PpgKn+eTnD
OfEb4@!$>CGzpsB+9uwE<V&ml2I>bcd?&-oOI>TLsq#N=*k&AF8cIm~`eSi#&6~9;JH3kc0g*a7B
tW>3XOP$7>^a9(D)pO@Jq7B#&%IR?6k09C5q%eLIW>*$L0+4o&6!G0BQ7Y}Vz34W`eC)BWRJ?!`>
oHOj5Z`{kZ5wDG7rW<8&Q8jW?Z$HgQ~tB1OUHCt&IHO)lK75f#!RfvNI?aKkw={Kbc6j)OKxrBFr
%A~hj$1sl|ikeH$R#7NLyH;aV=u%n2DMaL|z#F?eNNo#jtQyP~``?#Mq>`G|whtjY2TIWq)v)Gpf
CC!2(hlzo;fpMOD}^N?IV5zh6U<3!Thp?|tLCFxBnlu!bhxnzd8Vc=4@wu36s7(*JMs)0!qsorto
?fz3q1`~=ow>U#ZEc5ebI5aJdLR+o%<;ZgHehMxzcFVs1m8&x>RE6bb$Bet0uoSShQ&rR@56W3q%
|c74@WaQ6aMU>iCLH$w&y(>*XYrQkD!XXH7s5%qsQ@KHde}AiVs19u@F{gxQk{<0|YIt}rG*ceHO
p&^PdYwQXO$|Ml;2M(LCK4sh)Zlo`45B;^ct_>=&EV|Fd(e*W<7I~NtJt8C5AKtzAU+-|0nswZ!4
OjuryNmW(~IEbG3Y*=t_l8K?w4O}MIX_is&<5FlXqOC>{H?9#e8F)!c2E7H=;fO)V0!T<l(qdR?A
U>j#Wmf2b)h6L#Ar`@o;e5~*%M4-H7x9!F4%%b_!Le;tWheL>C+^ms@gQ5FdOH#8adCw$61peLwX
+CEv|i>P6LAsqTuF&2=V4q9x^8Yf7L=X@eah*f1vZwI85K5i_;E3&aGdA?fx;s;!1YB&r$`p0+EI
s_mJA<__(I@f?=rpC`*bSaa`;<`4ph94XC!|*7&&Zn2*Uq~s)-+u`34U^nr86%Mgc&@71bRcQA81
Ujx^$))4i&<olmEdA%&;(jD%mnBI$u(#uF5ELg$HU(G{<_Z3P6*ud65TiWyeLP4EyI_#{xs!(AM7
8=%rZifko~opgsaHCm{)NB-o*E1o&bcU362>f1c{l##HSiy2!Q4g@lz7New-ieS}TPpS<JU^P%ZO
(~9hQ&V;mgNF6;G+pK;rEO5rpQ$VJTEXVT22TBcgFqy<f6|otMh!NHlvR3lwFW#MzijQPYR1P{MA
ai#0q5e3zMPnHT%Rd)rZ5r6mFF%|YuqG@rH2hX)gcwgav)~kC3I^dC5jaRP?$o=R>_AaAU%aHsaP
=i87m~Hzx{55MR@TVe`L{PEJBK_g9A32YF0*I(H4*caSrAjxc;-+SY>!wF$K4U@FR83na{_!ufMG
^&I8-kiTpHd*u*NQZ3hj@Le{??e+>;?TrAP(;Nrd)tB4SaPa#Xlc5f4DVr+35K0kZ?f;?MG(-alk
)|Na_0t)Mkk4F_wwV1@22RP4lBvtX*FJnBIbqEThyrT#?eB*90Bt~^d8OAOX3OSjw`-|mPhcB<tm
k-VWx^u%YjFLk_KyADPEhmfu4qbA0Vl*a253nJza@)9z*PY-y#5CgAP)o?oRk$p&nEFO6Z7BB`+V
~b0^F&+|F)hAisC7hO<|1;f03F4COkwZaJ(Y(5em@D04xJ0_73=MLRYFqdDdUR8Zjx1nDDoJz@xa
=iP2<OQF;SUE@2@y~4;7NzGbLq`$z+S=2j(O(afmC~V7yZU-+G$a220VQD}oI%jzbWto7AWp$iX5
_6+=-+WVAL1UC;9shcUM>_90#w9D_Px4N1DItkWkXKJ%RzS34DJHEsAkA?I%iMTJeEx32hz@!cJB
?Zm3X^N$Ls%2bO1t~z56n1Nuh<^E#sQYG8D<z&5D1Z_c6%bSVuUy2y1K%XR*`x4&2+>%2i8_W1p2
Ya(rtN61F7IOm4n91HA4BCzZjg`it7^_*Zh=HL}1(>6b>_1z|A|HiD^jeYPEfRaH!;qKJ=D_~ODy
MF-!M%B6;ny#s{35awcu;z(R??)rV$8>#i-vDE*PN=MGMPA-u+`*?UNK;>-aZMei?@N_z@x$JY!g
(Pt6_96-WiOa@zM$IhNfeKfb@+oUp_zh`f<P0>9BW9QPz{|d?C9QYEqr6t4SLxwV@Vm1a#Y`Fbga
J16?iZDRsy#&SN&is{l+-NA$E9{D&1&cn#~|Yt3w#St@8)<(n5ewXv<8Q%_r4%G+SH^Ma_WN%s!f
pvWJ(kEAs7vd$9y#S$VczNl4I)x}rIm?sxfOI4owZ*V5&cSRcuDr!W8We%c<a-d>*?c7&mNO7_@E
LNA{^2_0qr-O^Vhv-H1kN@!%UDCIaL%bS&schjGFtB~BXl0dVkjE_c8R%q2f$!D*JUlY7z!Y%c{c
v!M7*#2xLuzBM(=p&`NYSY!DnR{oTduM%l{+`<gQwPEz_DP>`KQGTj__tHtKLY_mVNRN=QU-c6@5
yfp$tE7S2#{GE@&w=46_z$W3o;5dx=`hrcT;xi()w7;ka0-BMq3%WD>86q!!3g1<T+W!J$U>UKG{
CbF8uT6hjZWI}c~Bbz=Hhv+++V<NlZ6d?{a<RFFckMZ6Tvoq#}jos?CQzwID}>X^Mi4z`-nnJUJO
Q@BB23!8@JoGXsG9G-{LuqWn{$KI^cm5DNqKIENwew(<KW`yEoX4Z0{!o4aJG`B@4xSXrr>?nq{0
Ig2H*p*CXHv<z5A+>p_vc-=AK^+^<-f#mu$|~hJQ+slePB=4AyhgbRQ65dDkvFV!q+0x$6KhU^9^
jvfUeF1?C$5w+#0f5xU!n7LoT>Rrbc!oY9$LH;V;zP@q93>+bky~dXP-6lgLSW!q1SEUVvi@ZS24
fE5Dc|=ej8el3YNG)p*zM`FykVWpe}VPs$xf=8Ra})uC>RyPB&#jQ#hU&It3_w@<xJXKOlPT4`;5
dPbg{&wq<5Jq<Hb+9C^YaM%Ws0YZU&8`i32I2>(mD_<m!#O5kXYe5lh#$vV06+i$iHG7E#43XEb^
+OJgVCU~dAp#h|wGImxp^6Ze2*=4LKW&<*6-4tBS3vahQ4i_$|)b2xSZgm?quhi<+UM33dK8j5E$
!=x1I;oYkZ|rb)4Kurq*V`@bY_y>nKa`rLq+<}%q=vrG#NHN1E!$>?3}q?dM=Mx^1PdZ>l2Dj0)L
)=dva7=u(d7|cjv;TJVH%WP=cwbL7i|t45Py=semDCZgMmnxCQd!aN*LPswV2gbU_!~+k>6!49Sf
wQin?3Ioa2FZnTj7qIx8R>il7QRLqUHel$0<?-~ZQ7!Q>_;jhOaV)qzmkI`^o)pQl)B5?_lP%H<-
?8k6WHNV?H#8eKuO1#qn7*+jx@(Ey-P6T~X<WumC?0hn_Z7K>sTSmCd%09tOeEGlS)%%TR|la`9;
q>)=JIw@#FEu^;RdK?yDs6sDriaF!6tllDyG`+imqYpE@0!iW`5+tVsh~JZGbZ(OSX?hKZwAN2ZZ
JI3C^Bp+NS?)OSI^kE7+q=FJ;0pu9gP(&B-@be3qG>Dmbv3<CP|+qfnxtZ?xm^8={M18zecuYI%G
S?xSLZ`GEfQ-dyKs3&L92v&8OU~HrS@XBD)f2YQep@Uw4j|%I&DOJn|q<%OF?+V-D6-bnGhr@Rxg
mlkxJe^!>_;DXClqw_j(8(g_Ej;Zy9uyI@%l!q3XQ*ryf4#3)mN>O)LgDZ{jgabdR}I!5Wu|LkR(
ClG#<qx2rc2S4V14bpTC0vBRs|1wN9WDeoNPnc=UcCp5My0jxp{%u-KQg|%8{w>gAB7L@$Af8!YK
f=1*Us<N4>XT8zyeCDZGw%ovI7vjTtV63bKa%N)&D>ut29}nzrFSl!=41V#`2h|uSLdB?H6lqb}&
@K}@yrMc;br?m8ooFNo-5AQ<bcT?%wvN<TQovKXtK=+Og=#W$&ku<P*;fr}Hx#J2Dma@BIfb@Vur
rmQy-mH6L9p%?7HaZQpGqEp4=Q)>Ep2V6mySOjI7!&<YIy+uMVFt{leznBkVpM0T<(;t{Hmud4b!
W44P9c;vOI@d!8zL7(&uP%e=clPnlber0YhxFJg@-<0;reo+yF?`%r;;efT|kK^5H8#k*O;<O_l`
$m&#SZ_7W6O8J&2X=G7+kQzFfFTd8a}mgH`@JYlZabfFrN6f+=(p~7h2h9HtFxK9DQ#Z}X2h;-QO
8m!1gP5jU-E&}&ys<_lFXPqCP6K&;ZN6+{|w_{u6eJ*u(Nwsaf^u=ZZXT^_2PU9O7wc|*!nlM!Y#
>)K|2I3-n<bsu)XnThYmc+58c_Nd;QDi=YL00i${}dj%e#UPG^|mu{2M&942Nd32hqKkP|1Jyr@8
`FxjDTjl$y(WXkMmV0hURu-BavqTKiw1<=>|@<lI>ALTZe@|`+ViCHO7@&BP*s7cVvg4((RJ6m0n
Y(1sUg`82_c+4$?UW#}tp-Wm-CEoG^2en00WZ6Am2-J1WUBHXTNQxWa=+$<eT!%NVu`#-ILzjCqt
383qZ(%XpyehMNGP=9F*fW9pF1PTqa{Y(JhYZsOp>`OB9bH(3?h53$^`yuOUF<0*c*p&-ew$Z*`g
1gZwDo#H^`mLr{&WLUq<?<nkNP^NQN!zV|2)tLdWZKimjP>;b^!J!>Y>dt7@+@VN|%H`gU{(&9sp
U^yp*uq!R#~{RS;xxmLMz)0~S^9-#e9bJ1&&pE{W2B1Oc|>zRm?H;j!*7>wQUCS>Uv*r+&SW_`=!
d3qM7}dG<)6tcKsG?^XxwCs<@UQTvqB@Q?_Q8dSsldrGyI2doHcI+$F1O~6?FNhdS_ra{NnV3nTh
7K$a)gFfmZPKrrKirb;;YgF^N&5EG+^wXD$*M&&BQXI^Gqxf3P>vL7y<4_R_O&-@)%nhEoT>Yu-B
8S!CV~yMw{uh;eJ!$Irsy@|TuX$hHwSo=dV~Phhpa`wo8K7cCpFP+u>V`l&4E0hYM$AOEu;mSOE%
u0By6<muJbt}uV52ozhHw_!iSaY#f8kPsu{6y%aPfnj7AAs<N(lO4MAZHf<L#vk?{0VW@|f*}n9w
a|{u!#UFGzu_yV&SS2_V|FV^o$r(Ex>5;t%>h(8ru~CIrs5aDGnmWUWci-5k~-DC=4!pl*tptr!O
1kw24uu)S3T-;)xNjt+nc;34Nf{4AmHqpj}Lf)U2o0z2-`Pg)XRbLX6(gunZS|iH1n7TaOiJ_GqA
#}-=e(jR6O1U;CJ~Q!3u}r)cTrh(RDO#F{`4C`Way6b2N}H?25;Sn_&EQ7H9GDd7e=QY6{~#U@B#
i^6=o`coVcKqlwIT04H)>6!|2j010&RI`=|^i)>|%Dzk$D?%~5haQM4on5N1>ppVBETA8c-sVS#q
ld}>%cduYo#$@VvjQ+4v*M09he_7Yp;E+p)AzqWT0&;LD{3ckEn~F%dL_Bdx)_3eWf-RA3rJP5e&
=JT^71SZSQ9vi$T~yaIU?M7XJUFZcN3*g|Tq1c=0VDPRZs8$_TqfPsMx}yjsWJ;1tPSgZYEnI^U8
^go@AH@}DVkuuU+dtz@2Cq4>e#-30@quHCekhGuXxQjjLO!X5xvwA8cddB20LB2e9Ta@MwcBXZ3V
AaN)q2htCi}gW9K-~PS33%tl?3_h_sp~7_CsFv}-qk{19LZ&?%n_tMZ8M;pRB5=!I|`+GX`{)UcK
sf>DjVIzRtPVb8v|?s1K!spEXh*{_j4GZ{<`4R>n|b0xi?@Wf&*{tQ;>&ysoA?8wOu885GIo$&Ts
(?pu#x(OpyCMrAg6no;4B@;)jQW<^degZS%22Fv<FZS2~gjDq;D(Txt3-47k+mcYK^hYTBF0V1z<
NvTzEs|y4)>Mi)O*NhkY{M~0eWb0L(M)TFn~@WaY#A4t+-w|_?%TE)^XGZlnxvBZf>kTI!7)#0w?
22xfw?(Bq?K?+XPTk>GFw{*+UHOBsmG2tR=`OC{w+^X>Y*exyJQ4)ve-DuYeZSdx`DKk%x2q=Da#
F=7wbiGl2TA(Wr&~w;>mrptzDHAXFIg(`Es_kjp3Dd0J9oA=h>lakk0~*ira6GHC-l?GN%aGOHZb
q?fFBIlxayE?JFcRsKIoKr7n+HLuF+Ysb&Y15SUi53CU;!qKj3)jz&S?NbHc?74`)q#)v_$+R6zf
bjIWM;(`tUB#E6)M|Rx>9B@jN6c=_&rp%r)AQc7H<YO_zurxrP<AvBtplKcU^Y>L=vdctlHwFh?y
ylnW4}~@tw+XFmCwPIG1Te)xOnyxzj8f)`EdoD6#Wuph$_;=n^p!vvDkwQ;UZij24dJ9+sQJqK^9
P_tn1hZ>)G+z`<;C8YRSxiDvbI{t^5uL2vTij6fglAI7Snc|iO=ejvH(n{Ary^#uNf?!L;-dl$?x
<0Bf^#J*4!+P1IPNwhMa1<$|~#hnhy#wOAk3kA&LTZ+gBQrV*Wv#!h;(#a42KkJsW~%KRA)?)lfW
vR=7mN7;BbY>cwku(~=}nA1r4eeRWgIV91`gjcuas(ZhOv!p8D$zC~r<q+F6D-6DBy)Z5r$ojxl9
|7Q1w=4)3wWwN*dWvpti7&UwFzu981;)vr|tTL))QRHcDt2@o+DT*6c(NM7wsj3CeB^(7}k|Yk*z
G+Bw2aPS%l0gp#z5Zy>3^%hGgGz>AkJ-^-oiI2fQ4e2|p`Hp+$~)`<KxI#*!j(-InJsTWMft6#Hh
kgkZwg_=Y&$tAZrZ#!BcK-#l-r|<sM-+iHi{aiC$X~8TJXe5#zp4>ezFo(eGynOtgmqm@eo5zm9b
?ueEL9L@D>*rluT93%H`OiH`q7|uJ}eiYm<1uYrHYVWC(0oPr+};`A14-uSYH}6n1WeIGv&0tn~=
C`B*5scFV=H11(YA1CpNV4A#~QIP8Jq5;1a~OBP3&1Ww@c*RhI@Ls>%Ttup52{*69h({dZlZ6&UF
jn4ah03B3Ogu5Dnyv2jWq=1M=-f+HkqVNR;s-;_fu?7Ue6D@dR_n^4U(N9fVxpK@Zw)U|b^Vo|iN
dQCuJD8LS^Ml`_R<$M76G@27h%M6zGErhPO-{Pd>^H_xjk)zgtyagk0z$s!0Xj9TPiFD_avDphiG
Tu$D054WhjuuUqrDe3#4X<(=)Kv!Q`X&o&CCoph*rD1=qVPQ^Mop^9PQim^u&7YX|xg^Lxq2qn`+
_TaI^V%IN2kv<NM~}s^*CIGtv9KFsj7PwhdujqZ+0f^~mpJknq3_)U7>>*$Fw?b>N?C5^L$;Y_r(
fT$LxJ&)&+lQQ&yqbsN~K*X!wqIMQ)F{Pds_HYzQu4N?wpu{3T;^j|TxLH8tVR&8sN8m&#=@h&XQ
OB@%Jd88x|Qen`VLZH>bRt?}*FYAd*rmAyn6fetEi&NIXu54W-YAD)Jd8jRnQMs#ajQuq*BBc*}8
<;88iA=g`in{9p4Vrm7x-Ujz;SEvZod%lnj0JZ5r5S=AOUEj~GR=JkV7$xMJhB}c`mCk=1M9PebZ
@u`+R&j25yBl;<A%uhX!quBNSBLkNmM`J_0ec6B(tZ;Y%bxYt7`332QSe<q3o44-c60Rq16aX&2w
Oz(FRz3u7zmT8QyCxy1V6Ql@6mbHnCc4Fo3$?LDd_GbK%8s&H_cBvd|TBQsioLhG?TjDKeHe<&J{
+swh=@ROR_d=_@Nl-Ll!EsEcN$9BaP1mdJYTm+|eE6)VCVegjN5b0nLkWUF;zPOQ#rM=aa7KURF|
bAVJnf1c0s<p)&iI>D$w0szjOZB-{Xd0t?NR<%W)ui*xb&H(naGF{B#wPZJ^cus}#iifA@yPw2!X
}wcz4)cIhKPbMH2*0)*^JXxYD5C{v^cth@{(J!fVJ2Fecv)R#!grCneq-Ze_K>JpAlIBJey{N-b)
iAU(?RVNjZp4mO>`&@?H#W@ya`8Kwe+pmtAt}$y?ToW{QI}UxmP25+{9B3;Ef)b3l{hvYb$D+tCI
E?Lbob!>MWZ?xS&5G$m5x^IXaPVqw65P><z)!Wh&SLT@4ijvR{@S<su-ZKt@>;m{_L;pnz52NC_&
W5lYFdtOF!O4c!&R9F|lm)%Lh6HkZE3F{23jsK38Sm$1_dl^7kbd97QlykZ${g;%MC_6Uru6<MEa
Gz9D0cCkj-_X#ZA*`L`K1+r4=Vl8-(V}!09k)dWKjiY``#K!KrrsN{&_r!L(HW$C_qog|amB1y(G
PbF)x1dC@7zjo+78$Dx;(>$a-U>!a#^RRD>?_P-G`sUon+oAZz#@Km&RfNd*Bgj{fzoM!iuV1h@^
}8y+9$9^2fgJbDfonQ2if(s+nB!}?Rux{$eGLDtS$B`Y=8$7KJumKkKST#^OkwNw=^ozuyBKUz{M
WjTyJ<kFJ~LyYaYp4=68<{q3*w6q(@Ty`Pl@eQ9<^qfiLt1Yteeq783^wRbk)P*KO?H8HW<dOfA%
S-PX?W$}ygU4*MM8?SCqg013uw5Cqz$@(UGvEhJi|Z2CE72I>`|nW!pu8XmmqAk-Zo=gfw*01F+v
Mb@SjtQKR8IB{~ZM>Y#;{3q%|w6$57UD&h`x)syoPM0+bEGOzi!!VdQ4+XnNav<=k3+%R3q_t5Ms
gfGAzoJo6*Ri)j>=QTVliEg>#S|AF)M>3UvYGRuEQOrlmTbSRrrR^4xc6_fX0;vn;#1Apdhvns+<
H(nA$Q;$$|QYilg{u`@vjp0!^^zN;XroEdyyX~_P(e|)X|npH`4Hv_r4v46RHk2&Z|DRmY!U*bnm
}hoHfjW#rRz&FwlcX>eV8)lqGy|TmGD>G-wl|CM_}1>MS4AEsi&J_mZPAnG2hpf-`NnzZHeF)#@f
KlLVT=y9&DYwW?JDTj|?0`vl?GMH|#Fnw0Pn%(R4>dI+S*CgU4aXmkbEEH-b@H_0;8MuDmurDEQG
D=fD(N>MY|sO|G72hp(FqVY4D{9S>+*%GzUV$QZum5E7A+s&2#j0N3wQUBn=?yRTR>If5IS_h1#0
W$I9klqr{Z<$=jOLSu_8kn2~N$s_8;f?ziN^DrKe+NFexR71{8@F>sKcQ8ces-=N(X&yBDT(pwG5
Z`o((sV=7L2>5q+wGKZmDho3}_#YLWlK;yiF?4*zpDril%<hb<Xqy-~Ltopud>aQF`^KccgK|Q5^
r)WF5X>VXv9LZ#CMLBb2H&>EYIzIPF?Ze7LQq0At{TPg5NQtbq@JjkVZQnTPq}rw@-<1!!7O?^QU
8L!}Rd!o5aoX-j8dnqv2iO@onG5Ch-FRDmLV^8D`}n>J;#;u8@Rw`a4tgPmDzRwxS*A)}5p#*C!!
G5<O)yw3cIfrGXWrLT4B<=8?z2p)C2w3M6YD>=70Ir0Oijf%~5Q$SwH<f)=Vx_eXEf+wW9Q=i>vd
u&lev88H8yUcL<ZIDJzGh!n@P~$T3@tU<5LcvXB%U_G!$b;srRDwKgPEI>G$x&=M;oQW>O@|}4)|
sy6i%|E_l2R>lgUZSilUk@|&Zi#eyy*I3N*j8F_Il~4u9f<MHg&6*hd7aSt977PF)$+q5~YIYqn5
JVPU!&(|H>{B6C4Qbt4KgFPF6y-xP_Jx?DZi~L?&R1+-wc%wtzIO>1r`cQN5~dp@NWZ1=A^|Yos9
9ICQo-lrqx%EWS+0BlaX1iniGeRjDlXszE2UA~CYEc}Zi|NaqVD6}@R!cdQ#8T8)l4m?hrKL=Dq^
^;Xazv@XLUg8O^@itoAP<}0dGDOig6f_3(4KvB?!QCr|w%8Ew#r+iOMYdX+mLsg5KtjJUZx=i;l9
Q3-QMsq;69j)Cr)HNnT`}6>Ur$Mi~p;?Ng&(^W?92p9=lS~V3Xd!aLT8kc)5~C>FO}VnyR+}g8Kn
6P*>l*cv<MY|M#CROVM-@*@StS+d8Uh2sY&0DD5*;&^=`}}2E-j~vqU6*H*R%XGo)sWKGA@tD^kz
J^LwBbIx~9b$TI1r|7A*9nn#Q-p^PL>VMu9)TwiC~#%k~WfIASLb*l`h_j!D%x9y8*P$LMv41Csu
Vb%CmfG9+(AT#CKc-t5zTXR+QJaNK}Bj4EmZ4yAe43Kk?<bNKsNdO64Vs~^8C0;oCdOpr>`-QVS!
GfeTaVHr*lgm6Elho`90!3+)L0<43-1s!>vrE~H%mnBibnXD)jn8Eot_|NoNKoOfT9<{PB&4ON^!
`|_gFo$M<?OP;CV9f_68=+%E%4)NV3^1#_xmwL=p2CX&tfwn-%Q7>5c%NixjB~~F@Om|aS;Fv$p@
FtBcsF2Pvb>FF^bCk)8A~u2j5tBVz9WYug3GhCl&pd<YbaBQEk?OSQiPYNsICX-_Kqm@h8q#$j?Q
D)YX$UMq}Q<gK)<sRLqxDyF2}r?i(L{1YD8F3A7&I1E#e}3`R?@9+4%kWf1Lpi9`qj{9baUx&R>I
E{^9v|=yiXQz5e0V`1yCI@809rM@RhN?Yr|=r|*6qe}DG++YjI2tH=D}{n_(3uV1*Y`iEa%WbpOF
>9g;lv(uMnAAW|%M~4^LcR##*37!4)?EC|k>_PKy-<^GUcXozP-~asT*_-dFiLQA;%}50(|LXMob
?tetPd&l_YL8F9KmYdi*$e0SV_KQ--#q`%4?n*>8=t@a5lX#a({1zk$Fq0OPCuN#3Wz;6&!t5Mmw
Eid>*sG?!Jyy2r+2hp-@bW&{^9)1>+$>V-%!utL6_r_9AIdMBlsU9LcsS&@canAe+}Pz7~rD+HM&
Kg{q*78=~#vx+ObZ0^wX!G1Nu3npGWj_L_d$|hoW*+kF&2^_|xmk|2_G?FaICN|A+GbBl-Ub|F>e
Fj4xN|Y&u@#MT+}qjC@R}D4+6{$M|wz;e;$Vc@yQR$8&WkesYT!@OYLuXBEA8QVWDYmhQ&zUkfl&
{NSjeJiUMTFzCA-dG1G4jo#x*NP}TYwpjELn;T)cu3qru30JA4?f~{H(Gde2{CIZy9=D_)oLqJ?i
;E)o{u4)K4A02h2MQTC^P;dzV&oMk>ddS6&)OW=SNuTH@M0s~0kXs=#Z{UmPG)HnLux!uv$PzKL-
Z<l<L$D&)a<I0W{Z_dNmh9UQ*~F4p2CO#6jxWt(*Lp;Q%oYu*8+!v25J;tgvL?{t)P2*!tOeHT(w
k?<o}`G4pqHT)k0mGs|(L6RI}~2K<QQzm`{RXCQ=NSg08!A5VF<QT^@W&mbnVp&B{+$kdA*I?dm+
xioairDw+cCppk|+5Ip^OMMMJ;dDg_8mSRe5Xj2eE4%AQu_hnbX&@71^&9JxewT?+a`{+0d{s9ec
LXfcf=pO;8da-(VK)d@0W5znj6Gd*wu|_1@=X1(TJjn{Q7G-?Tu%JD6&IVX%;|Z4=cyP!9V`TTTN
Rp3DeIQ>=L83fb3bRy|CsiOleJa4==G~>Gd?yXPdv>T95r%i|Gsjw6mL~#+9Rc4y;o?=K+c+*+95
pBP?p9$OfwlTp7J?>SeJ9Ynt)c!6OsZJVWi&TUBe7W?yUR7&h23=c=rBXO>F@yDWUE;EDHhM*Q_W
XsdXGnw!FJU~#WjTx6Ai|FX0*`8)2B^_F4TixA?77A2%0$@BX9!35d-h=q*<=~1_OBd;P9cJ8piw
;yB6b-u4ibp`2jXC^&ZiQwDeB^p+_0S8Q{^sWG3#KrX%lAXt)h4*>KfnqvuTrrZI%NqdJblQwK}q
JO62D69k6>8|L9Vp7)^foTuS8ZNeFaC1AEMq>{iERV0Gy_H&uVkeMhU7yH~DGLhA4{NjWQRNpa;R
8+*>o%2PB22(nHfSM<9U^S32--G_DW0aex$yhEafvF-4CK<28&6%tVGm4hSLM~Y$1R#RW0GkpwQY
e|i$V|+%tamaKGcEIu`%o`uwpFi!sR6LXWLFt4dOx0HAXcF!m5y*<%4@4E93#&4A?fF#WVV_+JU&
kWO<X;Bz;ILO!Zi2DZ|l#KCH%*PY|_zZ`?}AP_zDGp+~chy+>e^AcNkdasRe~5a^j?@@EJCY&9qg
AQKLB_QWYFI1@~GvT<p@+>P)F#JfZTgT$K|m(KsI`UU9{p-Cj9pr)9NLor#=vxOOMP0NBkDDT23`
`AltSIut6%h8aisC36|o*LIV{?>}J%&V%RGR~ClT2IxK7irE^iTY;n8_&)^E6|SEAv&d?83_<zGk
Ion~)5T~6R=a*o)Mg8<%MrctfZje(<<`B{ayf08#;&ETLdXsM#u8Ou;V2@=Mgyc6v0&$E?KU;Dk7
9clZ7GTa*}b@;G1g?8tJn}}HX;)AvD<G3A8vX<w6OOG&<D|q#I@cA_%#r|&&9CKORxhG-gtgAlVR
z%Mv7~^2|Qh2CSzh?YJ7^1x2afaF^^4LPE?ONfN|t!aJF@6KhM~qj`@n=z~W6tez(dB`+ONs1I<D
c|54?eodK%@MscAph}BvSHfoz%qUatYjcG|l#xc{+s?ZG62ZVZZVpqYh{oXdc$qJ;oh1`*F<$%-t
L>~DSrh?kHs=XP#m!2ieEgdt~V7!H$fTPt$8rlau$~?L=x=`8p((_!Rr`BI+*3$ucRdCVDprzLPE
c=18QRyMy<&5b<q=vi<Tk@*|Nk}3HdUS(SLXXS;8lwl|5>+n%YFf(@lSAMw6)#rTTY!w0lcpiV`8
Q_xAy&Be0Ye)L+klxw6c4J}IG_xeFyTZAWnulwq!rX|OR9K*Fsrm<u6p)S1rOrYF$grZ`<2MM>SI
r1_1hp~jH)*?)du5PdYusjRbw!Y+P#gVp~A$RW2OJ3TY1>}_pRWzvg7X+&BqeawoQ)IM#)p?+^7Q
379Qe-4G!<|6u7Ms@q3)N8t(tZ%inY|Ps*EoYR!Od4##S2H2P2fw$a~m+yR<FJNV@EigzYeRnIM*
tdDn4i(#v>D&(!)QumZV(H&hoo-g-?S?qTspL$fVpUxkGwkEPFfuR3@Q}z4@o%f)UDz#NsovIx~>
J5wqM9$c3eFCp8_E;dP?h#iczo+1S%c87mjPLPc0zgz5>8IM19mS)XXWgdl69poB>^Y^^J}8>d>K
jDVbraKcubR~RQsZ<rxHH|%@!*bk8{8utT)+G89^Kcwjjq=Kx=;N-v~rHJ+Djw)(Z2)|x6w{sVw=
b28QPXE4fPPc8ZjY4KqUCPX6lIFscGfV5B?{WFoI1+1}ZNv<<cNqix&H=b1xVeflYikrofblWyj{
ne|r5)9E?eON6~=EP(y4yR48Y%P~qT}<h~ArK!(7LTc$_BnS$7W1>+3Hm}is;fHB!<iE#=>|HYvR
`w(ZAGdh;|&gQHOtpxyr{wmM%Z((3x(uJ|G(eHT#MUs5<c<hsr6fuB2ehMmZA5Y5JTD<+qdaS0lt
TDay>}4*mXtR|2_R9Jd)OIREjtXz#LJfhWB%@F6Uhc9nuHmGO&6T{>nJFlnfb$mJx=ew_TQ@yIM+
@b${8a|NTFxzE$Eur-6^9<yfXG9m)aI6v&%VuMW2u_fH#x?;76&e-zB>zZvB|@DVus|8URUMn2mT
wJ8bPfW`_&z^bF=f8=8Gv`>qiYvHNWmy)-M`_Dd{tg@Dl3RhDxq{Q&pxC87JvXnl#H$4?$sVsK2O
e==Q_5v&)`X4f|Xl?Oq#Osg9NKZCvKlT-CB<%YD1ic1<w#T})c-J@qcAns-eI+_3&vb+ONu`y7)k
gke}0BL7-f<knV}QAS<2H6U1B0Ii_gLG&-d;^Xb((X^S-__zU!H^||&#;WMDVM#DddCj`671Ry!w
)lH)Txw}{TbMUE^gbFs>NwiLfzuXYNlf`T+I?+(6jQb37hQI`wnlMAN!5P6o8JzFgf}J5aFVr0M}
MRyr605P3sq&v=0JTK7Fy=o4H#ZPU>iF?L1B<B<_){|XUC&WN6bcr(B|lTHQ>q4VZeL!DchF97CY
<8;;1PM;OEfEZM5+7V4!=(onjgG?FewHCWbb>t%zFf#K%&2D|l@YYepNIjVeOlsZbTtdi`kY&gxR
6$+E+-1UdWQ>T1}f?1_LdWVE@%-tPI^IUF2+UORn%JI5HiafgPs1f2BlUbgc`oV3E3J6AFwoQzT5
b>cmoyo`jd^VH%yn(p0A`=+eNjLGmX?Gs(8ffcMCpiYf#tk0iwXxgWD^Joo!X39U^xHrigC1LZ{E
gBF-X*UyPr@<%YP}v&40ol!AmGz{o&sK{&5E=VMWqX(eXHmD5ZN9hnLK7O)v)@#uoZJ|e&S~MVfy
bL;3-s;QPJHzTTUndh*+l2jA7N}{AadV~d92YV2?IsoZA4lG)bd73R)f+0W-PVF9qkBpXi<CBG%>
=2UNcI#<1EqBr}hny513SG`vJ)#(sy@qpfuNEHb5Hh?Q;4qd#&0PUspZq{R>Ce-)VIH4WsM-*`q7
A#r7~RBzh6iR{Dr94UC`95MPb93=c&$$9IHlfvDYYGOlhif1zRFNQ@HUpOc~7hJ%B_PNCFzP8dHW
tcXtBP&+t?=yo*voC!J&Z`$M{EPYnvgpxeE9R!38L*XfYR^Nsl+iAB|uiv}76vu5d|Ezs7-$d-xI
p7?pF5P@;t4cpt)T5S=w`RX4QKq6dWCP=<{Y@|^?a3A;RaGHlk9&s$R6z8!*30(8)7Joh`y&S^Lr
Ge@Ox76wo3AFe9-6=EX-oC?XTVG*^Xq4=@y;_4UHP^d6w66);;7@>O?ob8%uj-J7ovv@+OONoF+c
t57Czd;%OawV^aO@5o6&Cd3B$Lut~Qu<Fa7HdjIIIx7Rtl0Nq2<JKLeM~fXVLgNVmXZ2R?zpM5Aj
v+wK1sfZJsCYspo+QD2|*=GNRQ@o!Kg{3&WPzH8m}@bOJ(v+Q0`Xsg1}#z1$B3^cO+psLN@a?4@C
uIqzYBmVy}<&Uk)dD4jb#1NbW?ai>lJ6<gK)T^WU9KDqsQRpfbOP+wnv#CiRgta}fOlv66u3f$XG
rIA<uQpt^iBM;$ZP*Y{La@RE{07CXpZsjs)iyNu*P!=kV|$jTs;_Qs*jJ1CZDpkdrC-(X^AFQia%
;h<axLs$&8kat3cJC<a0*|%9dj!`99$I^dA?c<VEFq`ZRAfPmSm`Kzam>w&*q!@_vB=?WUBz@vbR
P^%w4x<s-7T+bRJD%zA~~VS4U`2W;<;-d^RO&!T9Y2=liqc4LelkxcMyFtc{B=3p|KD3UK<Z<}jF
|IoK$&wc)LxAn8&iwrrS4TSochM0fT?!+oPa4Ejr{Ds44cH0GCQPZ1GG&!C>{2hB@YK|(bpIt^!?
GM9NDe(n@$9S<8knDhcYYBEreumIN9*vVkcsqEWHZWTPZ<{aRT=h=c%l?lPSp%~K)lu^xoK&oZa+
i;MLYSqRv$;@Nvs;qfxZ;jzmo8Ecq+NKxH)XO46^_}25TTV{42y2@?4(w)a$Ag_(t$Hdn*kXA!FL
h3WO46ZF=5oF{=dss%iv!#kqcXO1DncET%FN-Ud*AEAzsQNV!e)0>)5KyBgcZ9+@+66ZMVu}vnVd
Ki+m?1J<KD88p}98KESExhf@NNEqKDNyBnnRVkS*$zLdsF`NZHYmsUQ>=qrvc!GQrrhr5jP^phJr
H*5W=QJLaV^CyPwfA3blk?~0Ay{)rk!$FT`@YP*qjHm_XBZbFWeN_G8?t>r`8Zc9h-*C2FN297~c
Z3QgvAe9#~4i*@OoWhRXnH1_Wcm-+4nW+KLu6L7d9BCPw+GdhclHYPHxMg}h=Fp{9M7Ve9waOTb9
F55gS_HYu{rp`#%Y)}<LGdw}C1uXJdSAW`;^mx!z`a{#I_KxJSwczX!e4&5l#lH;TAf}mDZzHTy;
zqwImO@8!-1z5WAK+>q7H|Y!=N}ApwGmLlO)uI9t|*jKre#gCS6Eywcgk5OH6$SJ*SIq@0VXLGWZ
~j8WuQstO^ij{qhT&<hK{e65}k=e1f+*CPX9CSIoG*C?zD%{34?q#h6AHTF^klRyZ~CJVtJM9h~v
2HV3{thdF+OK?mo_@>;UAr4*n0I?3lriI%`uXh)k8nWF5)IBH7ZoY7;9tBN}W!|C2oqT_t|kt4uy
t}l#q*CBA@)1Y&8c~5T<R$sC~bm!N3L7_uA(kHFkYsvdX(Gn?eVjTQ^1#&({(hFXtoF{ETNg4p*5
{?phcN3SGcFZIk<E4P@mnV$)6O>{Gl8L!UC`Bg+a^<*yl&gkTHU5}n+$<%aQ&C^PEMV;@Z79ca#l
Q-Z`Wewa$s_<C5qDs2@CJ<vr79^aP4I`p<QLG`c-f4D?Kbykc0{|4Xo#X+Q9|X(O`2Tkjldwct)h
qRHgFghd+>{}NeYbc1+E}8cAZS=YnHcRnbb#E9sY=?^y|}CXCpg)UplAog%oU8eF0(fMt{M82J*3
37gm+a#rh&6_+oiXHBkie>c?bK<|J!!oGRWc7&dVQz*%zGMcQqv41*YfaM9(D9F-q&HwnUSr+d&n
JPzh$2ahqRzrZM)anS1=AHdVA^m;{x^tAd%stH)=83zo;Z<Naj76jd1y0CQLoqqpj{KM<>5AVls&
)$t+p_3b4qIIFS;9+pkfgX9}e<N?4OCk+G{_`axXbU%@qD8dnDJ?|s0|uJBl5}{O#EuN&ai>AAFV
0@RdG~7k?9J;lio2&ybs{IhBAMN$1?N)XC&ePolG=lw{Ul3J2VlN)zLJ*P@+_Fl;@fmGa~hiks|8
Rdz$5o5j6SJ7#JyE(cj;|+>1}uEYj^2ycZTHg`o<l>B%WPW2b!0jG1clWYju~Vu643wE*EVI2w%u
2WnFae<4}F*V3=r3Cfjafl<EDTHyGi`&JW11SxT~GG#sfgdK7aNV{x0v*cW@667cX~|LPQDw9V~r
6y<fmrLL2yCj>myxV*<QC@x`@U%4OkRb}JD79|chO~>%pqVJ`L9MKM^;she&e1HTLD(8ljx|8V21
R<Gdi=abu<BvEm{zP-)k36`l3X$P9#Ab*6!D!@kP4NdRf&o9LAexR!mB)R;T@h{6p=~RD2^2?l*I
TE9-sTP%^bH-*%g^edCWKatDMx?m!XPyqcbLbzu=3id$j3uik&z1Ltjd_06qa^eOp?rm-UM>r$rn
ZEZqAq87%V?uuF(ezvpf};cap6_mBg+$7lq2F?8TDt=q}Cx?@7O1oFGQJV$La5kOZXp<*#s>Afp>
=z6}*7%+G+7zr+)o#_E%AutSVQPH92iG)k0&u^z-qZCg4)aMs90cV_7&(6uxvIw&#7JZ5S3@q`l|
q90eNk}FB<_kkTE2A_0zGN>9G>O89^6A@NcMPv~1bjtD3M@Hu160CqAJ7l|Q*WK4CTKKZb*Hu)A&
(``7Gi0^Xp<4+AC-iL>+}be0k`hkdmmOZONj{q;6fRi}zk?tRt?n$DnqZ+4FVu_3@=+;+e8hT;W6
Y<4YGUa|EsY19+u+zyw=#gI?_QmL_~G4IZL`ZztXj?xIcXs?8SQ`ipJtW|HD}H1G6!n%61v;$jP{
qDPMj5)Qy~RbiUfFK(n-{{2(-PL^HDbDbCBJ+Wk(_fBL#%p3JywWmzmn;eN3q%c+<im`Z<Xs>|`3
0M1uA|7t@M}RaV`kCfR@)I|qE%C*#nGc)|;C;wCzfgo%_5@HZ>r3Z{Cf6s;!w6bQ3OrV{MIQWw%3
fxnh%w7zR8yj=4NLlbZwEN1Z}fgT>>yr5{2EGkI>Dl3hx)}vVg7<E=go?MIiS8XvqJU|ClOc-F6h
Gnap_%;cY=xfVPDy0B+5OKzZO{=2Q6$&O%JwsAh$f2yFHo{(_h`_fQWvI^$MQ~I$f!83v00<D!82
%B1^&&!3lOWdS;~N;(7z4+1_6|<Hj*5dqgkj7ypjxxiy`v-^-zVgSyw-lUF*hK*CM^5iGA~KxG4I
sQb<709BMI@8#mSxUo-xT%e?}O=MDOC|)Ox0N0&osU4~8~T^$^)Ac&cZW94`z~*;SZ%m3(QpHO_-
*q}s2}-hT%in2k|9X`q4+;1GY{=IQ|4*(K$(od}aq6jrw^bV3eXB%U!oPbcVDs}geHn0azK>nD9T
*%t*5xsX9b>}<>rL;lkuZo<+!5(%JJbw<bJ&XuGcY7kEyV_k(H3{BYDcw~=3z71nKx&Z-RoV`E${
_Ob&hX8q2rZy6xWqOsQaoj<bYag3=xJ{G0@ho1$S)|wo9Lg<jKJH@J9W_pXmdI+^;MGojXlw+oYg
+G+pLZm+F$p&IbDCxCrCwhwW7gN91~$i|ILtAp8mn;6wx$&|VVKjIRVoD^hE96tZ;W0LS;S9RnDi
(*cELHdbcGbD{fS#x14Xba;>#jv-}Bo~@U|1Y&kgNDQU<Mad*OX6SYv31p#3xmKT+U@bwnWwfC~n
J9bF7_OFzUn-esOokyes=WtQj5jy-F+DX?$}IKE|iKL*)shU?Vys&kIHpVD%z1Ha6fhS?Pi3peMq
A%HC*?&RbiFs1`@FkkNNFKgcB{6K91O#?>mK8-7xmKZG*p}J$EQoKqem=60Rz5*ctW7DyfTZu7)>
?`j#m&dU0)VL&j!397Sm4jlzSAkD)76lKf11{7GdP!T^Va(I%_@1njaljaZmpZpQ-si#j-eJT2PS
-TGHcj<5G}YVElv#|H0mP?t5jyMAQgyAx&})hV5r}rtKAt8T0e}c{tw7%O)VsBL*Kjj#)<-Rcu41
8NXSKkr!J*3w6{z7adB;5H^sek}LyFLl7xY2r;Hq}6Ss0GQs6tj6*1RPni~c+jrcG*6Hi{Fm4bCP
w2CmV8r3jVyR=o`+ovc>D5;?h{M9`SsKB6>%QZpbL>WD6?byUp#Zm@%zvuZNQCM~cl6XK(e65eh7
ZY}5(_cPQLMwE*Hzul0pZVvFIG|eHVi^u0Ue&@L>HmN2D$OFc~G`*rc5XkUh`%`_5Fu=4!qDZ;a$
NlF`_0OJz4#mPvn&Xakfm(EsE+hdKJ#Gco!YV!OEN5Rsc!n|RQUA?bgZ-<DzoW(w3w8996&#3Do9
U5)PmpwdUFVUwcWFK9*!H2U022z^?Q~m2ntS-6Qfr!*A&mn`k?yks4_${)7zi3q?<?siGMy`U;hu
510=1ARwqMOwm>Hxv=~s4*z%{s|O^(-a@pX*p#+(bnJOH+4HWT#^h-8XS!V5yp8azV`g7KDCYnXA
ZPzN<$^Uabr-rr7Di<o=Ly$^;(5!zVfd_M|kTLcOPkhW1Iq^a5Q7;cF%1+Rxoj0J=DcbF!P!l-j|
ncOBW^Sgqt^{#=1W0{C@6Y{VN*&@qT=3y!<LeW5$q%(@!bP{0R`%o2<cX&m;AX1Z2Fe#h#^2svhB
AqO`3$e@zaq^CakUIEX!G0TKQ$6sEa?9{E`oyzyB@rH;Nc;cO9DG*zr3qc)ov7^TF0qi)ahIJe@=
E1gRC8|C$hm@QhZS2<H81VQWPLJ==a<u%Y+nZS8;<E{I50b6WT(+NCovo_lt=^J+vQi7jUb6J?iS
O?X%1UE#<44WDOU42B0FGa&&sBwUL$+RGw9K+B9aIN2I7(q;e^NB12k9jM(ctJz}7%*lN;_t8QsV
?RK{}WBt-T)U6<DLXljKkbe?gLlf`%9=`<Y5>hpDvZr~vg2u0p^XK%kheST&c^x8<ah?nfOt@cVI
pUx%6DX)iB!{yfLJ>s0=jB+^rQnD{{8kNV^egerzjRDhQuNU-4t8gpriPTpcIkR2FuCTrU`K~G75
_9s(I#-3VHSOK#Pi2~bZ4%2fIS`V2QcV2{JEP%Pu=Q0;;>6}f6iCL3Bj6m=l;U%`=6mftpLLRZmy
1$F&u|9YSc{Q5_DG!hP1hSR+aRk=jKj93gl(HqE-@Ix#ojkxeDOu_-P!4jvv&b}WUb6`zuV<c^!m
rMckj>Nyf*J2TQ6U~d2#lhUs>8*LjRT?N|LQWR!3&sGbktToI-yB)BmpR>V6Y9g809}3zDrP79?#
S=pprby;fJH_t48jCC;*(!X>B#BMc$rl>fc+x!(q^A9)C1uh%=Xv$L}^zuA=lGLgx53Rd!JO-gZ!
9$z>yz<b`{D=@bl?SKZvB<3GNYeBDV=bP1{@thvSGWE66G6ICSUwrrZ_&=8LVB0S3K*tX(?l3&lb
RbM%y^pJ7`aH<zbD+VI6f8ua2l;%K&%JR3Q;)y0T@Iu8-S6+;T>D-3fTS<#Wo4uklbQ>?EY>^cPM
fQG*1G=g&p6V6eb)tTc4UO|uss<GlpVJSi?w-)x_WBgW&M(V|9r2mMW3Qhc7TZAynpKm^4FLQGzl
1%eW9N$x?{d)hdKQW4GYhnc~MvOufKhya3LFCE6_2bb7*A-gMWkbDYsDk-2|X9p<Xl86ut0u6U7S
k*^-2S3&7a8db-MTYvOQ`b4{l5-x^p-!4JJGvbCI{Dy=f*-G&QM{wy6nDs(NLy%Z~+$z3Zh%eZ&<
;>>a6V9Iyse|bD5))Nb9msr0r(wutmzVnKFaID(RoM>lg!E}6CMu9G+C$MN7GN-&aV}igYEW@2Ba
h}%lcqYtcM_ndHMXNr&3RO-=r5pB=%7#2~3_%sjl@VVV<!ENx$DO)H3ENL<gQcO=5*d1d))=1B=r
d32r<6O%YN5_DRLK10d7#4eWWF8Dw@|5vv)|B6c|)_Vkt5koJUKE?j!rzO+%l%BGEFYH9Yucrgv+
<sJ#q{{o&Wwh=XfU&ksWP=PGJK|+3*G?ROgotXJNl5c8|zhTtHkvy~V+8aRL<-c78FWzn*?^Ec9r
;xPiIz!!Oqf%V*sz4|g1LkGLcES}$VXtj!u&?iY9w4Eq^{y`rPy=@A@mSEpmq&>&bDt>zo=ATXzv
i+FF%cu=s|&th|(kv>?{l>ZOQQl~SX-p@;5kK$TU#Z1NjTRTDI{5N<8gJWKx47~gB6Zd}Jg`3z1x
QV*`bFrXnn5ck}V6gzZuoQfuAY?hb_7eh;*{-1mp&MVWdQNVRSyOCQ;;IAeL740@RC{iO_QW6U(A
+h9{|8m+U@>bzT(Mzxu0hx}bog@1Fvm6vkTQI8DnQXPg_2=JIeNHOsEQeZ57yIX!vCl8lP=9#%;N
pz(&DbNXf+qY7q%o<)U0^gCn4s_smiBGOGLClSKl|w8KUj&@*6w4<J~buTn`5)`x};Jf0=HqM!QB
&E#~Zo;E1~KWCg-nOG_P=ji`z;LKv$yRxFbXAt1bfF|!pVfDhRQvF~&e!M$v&1k_UcY^SRU`7!cB
yp36VWgI+hf#+7vfF9>%gy#hth7dkg^OuEz@&e$-&%z+vAHh8rCL06e&nB^BuIRKas*SrA_h%VvU
3Cw4#|O@^pAYdsw@t(80}24bAaP9|={;wmP_9U?y>E74Yv1ZRf-X)RFoZ>KvA+ZvAF-^yC9qcJL9
iAA<z{p^t%BjxE5b-;DU=r&?b~GjoCsnIO=3Vfy(c_PoEx0EZ469u=d@R{mS%^jyG`;;g!wb_nBi
@h0==e_cTsLkndH)nB*W8_P`GYp8URKJtcv-a;3YMPuWNf8cD9wUi%I1iBJ67l1}I3cRf=5Cu;3^
diUmaoMnMsLL{d<Qq+T6((6rlTy~Z!l%w`WZ+c)3#9t_}t>wA!-CydN;mJ*^GNE$&U&@bG5u=R7B
dOOTBS<P{FbK%6xrN9B|r_4bj91^IaV2PT5B6ZGgFh|w9<#qx#WF7=Rp=s1)R4Bq_N`{k`y(T7vr
kHAX<QE-C-!Cp<790@tg|v@HI~{?8;63dAfz};va%<#AzPxe;i8^*vdUzi}?xf&TR-LhQk%NX_pM
X|UMJJ6`AH~BD4Jd`lJ<tMUd3rC1E7^e+fg|||JN_glAS5nU^4vJ2-UV7QeqC#zw6ZD%>y0%%Sb#
J}Drudhq~#H?u&p2GRozx-?jW+z!VB%|Jc|z>n5iD}%EW5r2(c}W14~A`UM|qX9h-{@ByFr#^4!x
92rx7(;jE58794+k*tOmE<Vl|Q+k)N(oI(0RoUJuUD3c|eJpLh=FD*KWtr?6Bb-dWQa6Uiy5>g=y
=41k(H%sp_LXvh4Ux{VP*F+a#iVM?)tm4!v7?R6FMUa?Ess$$g{No?h$G2~;af{3AM7ow)z;O=D7
dH|$Fd)^JJf%N%IpjCj0}~8+iLt=rEm6R$im|U14Z*5184H-P1_s+U<CO@ebHDrzDw!g^
