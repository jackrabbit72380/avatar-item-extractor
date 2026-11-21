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
c-rlK3wztPvfy9AaW|)ABPo*nh^xlg>m*L=d-M8Yx3@jAR;47$VnUIsNZC?)dVl-Q0{{V#l$18-e
!Jgp>(~;B=U_0H7iNAx2=0PBSPti5Hft?52fc%@{`P2<Egy}d<WZR1iNz+LrODw<a&v(HzX-?aBo
tgr%;9sKiFB2VbSlp2;dz#Y`MY5Jv6ZJ|5hZyl-ah;H7BrAt&!SAgPd*F9Jj${txfOAgd=%4kNe>
TSh`T7f@6ne9v>~!QU51$mgYirR*fRVU!A<guxc>hAqpR!p&%`)Q@*qmWrMRD^StwrPpu{Lnp}H4
M#G#LU24XyeQaH|6|M<B%PUj0~I148?2^G!6ER82PqCkwIyotSs6G3nhZ_<2*uV&#gg#K3XM2tdl
yP^if&8pk(9Em80dBkygPZPXJU{doS7twqXhx0JWq2y>Ifh5jX%RqSJWsry2BZg*^D`X95DGTE%3
}lfm5wbVQI!vPA>r8wMmq{2uS_gAkDf1iRKFVhVF_@T`&;l(1@FM=Sh9xD)3;0j2q_9_9G-;~hNy
X|tg_jKU*FhXUOD9-59eogU_}YRG*!1%>nMTVw%r3YE0B1Q3C7VTy1w6yHd&a<EcKDhW&RnPkOa)
&C2`q^2Z4-s@Bom#^;bU<ZF7s#%xbR4HyC+8?Uq(T48^Z(dWjI$gI^DxAmN+^-@@eMp(k#lOG|6D
y<{_affacldn-?O3!G#Txq>NO6YtTC`^EA3$EyG?h>v<St@FcrQI<3dwiXcv*)LM9}1%SWPI_}6v
n}%q&V66P@6HP~qf{)lJpvP@=2g6O15U?l70rlsjn*>k*&<dauB#3&@T}xa8h!`&8V7ZK-(jr_o5
dz^FUWCwU1Vcq=U=R0UbUQ=D$<mty!K+~v0KP8Lj8Tu)<zpC!d7221mVi4s_5~p7WEtFxJer3sfm
kpf#k3o45)Bu*>v6mxAZsX+FofmNZ9asLQIbGWK+0JJTNXARg4fssHwo7Mj<$Rt$3|pC<mn^;0ET
PA`sp&ATbo6KGDJw_w6y=ZjPg88#9a`tin+?w#^MS^G_cYn-r#PAeHL?tILHxFH;LTuSnbE3_}wg
kO*oBH*pmo<cn-xk;SvT9)d0l<f(ip62_u9{OA$&OAWR#l5-e{Cz4e0+Sz5eJGyO5km#cAJeBES5
E3ljK+tuawZ_clOe19>#y8Oq5I1}x4=cs*?JbU%_`F{+5xHx}t@m{^^bOA_!>2LqDD16#(x3L{A|
K|Ml#T7jNok>KyCvFZd698y5xjAU?!wx<?hhYQ=S^c<+kFUdZ4jV&1Jj92zul1uNd~`Jn7U5e!%V
h*KK)*YtcM^T{(-Z0t>CWpg4<>*DKPFH$gWkhpSdX#P^A#Kr^XF-tF0TXF82asLsg0kk7XCmO+$7
@|=o{{Hq`l$9yI7CI1y0lNNumkwx#(9w`~KR0c&^|Yhrzt)`&pD<(IeR*W6!IrXHB50Kuoa?yhf6
q0uW#y=R_y@6qP$to*Y19r*IGgsc98Rh>gN?F&suoln;j<o-GZ5AW@UV|L|!G9|AVuALmUvo#HtF
805UjqEF!v2ARP-AWR;$E4~q@X5ZskIQ}R*PF8a&Z+0F{tzI7LLgJ~@i%|*xTLuxH_<H?r4iH`ls
O2g_qV`}Syoc}$j{OG{|K>nE5T4OhF`S0ek?)%mz!lg&eq+QZM>|J}?ZLS{QG_4PGpu}b;5*=D$m
u?dw{RM*Vs}Ai(bRdQ*Ugx8@iq>rylTF90n{7FCcS<NRKcDO6a`!wA|^s**~0@|akEs8wE7JAyu>
>dO|w#i8usnt^C0^O#l4Pr@`UR8P^n{=AwsX_f{50aoj-jl4hQ(#=*3wA2G>8K2kPnX+?bEO5!me
F49SOQG!pw20i{{>Mq#h}&O+@fXfHz`qKO=%i+01+DHT`f=i(hK(CJQmTb&9Q<xa~OC&xkKC5%t}
@@P6IG!k<drFxx{ii(Hb-4zeJ<%&^7#XE%sMJ=bzJ3t>sCU}d0x`Q>B4?4a8u?5(qa$hG$wZOLfO
nhe<kaH;d@DfB{-*;B#4l#!cB;^s8Ml;<4GGY~4E8<&VfuBs_SW{2cvrBqrg30&$?Sa`(Fu4noaa
c89lm7Vi*le{HN4Lo^PlpNc1+)uG<F`)}&nEkieE{HpJ+2%>+y7$ca25h%7z3qWX2n7LQ#b}$^Gd
(6&tqm2o4>7sB!{;XEDp@hD9DiM1Sz)x!r?l&O_LyoWe67yV%dW=aKLyZ!N$vH+3sVR*@F_msNdl
d7|s<Qv|OsCk;Gjd9M*8XZ^6yJ1wZXm5GDf>GK|*kU(vCX`YM~xukvZ%D!`NG0S~GK(Qibz)vheR
sVVP41&}ijTWw@^yc78L%{L(Y9anezsjitrvtlK`QO1a`NIsO3iy$ztz_Lm**ni=qr{y3%fMI9-2
Av^V!k>?%Ffg0@4MpO1tJVEqgr?0-OI$%iP1wXCOMbt>i5P+mBSK)UHl!61o)(YC!8|nELm`_4Wj
t<(Fb3IXJ`X`2LyZuOBOs3KVYA(O-0Aq=iF6SrO{oTnqtVxy+1w-@XOCXKegFFW`l>ab0MHLnRtG
+qcwju_Rxt~R$bji#jQ}zerBg7PLq!Bm3M#|y1x{MQ4Zyxwrjyl}Tb_d~8jSN8RVb>ugVdgj^S<U
~&5b~(je%gB?X7I8TG^CZ`Lw;2PgSjaDzyTORbaWK2M_Hn@Qv8m<v&^FKiTC!LHSSC;kW^+-f>Ps
Zss9!eCAFv+p+sxTYawWKG#rnZT0C<r@r_b^zey3Rt#W`1Ax6}cf2m0wjLF3Fs%5`C*PDHe?n%m=
InTeX9TmZi+F{KrfIYeCr#RG1@2Mb`yLPtA!Qb-d-gJbMJ*i~7E4XygUwP)frolOlTB5SeFw`NIf
RPwRJN8=sK`b45|S8Z#bM2ds0c<N-$8w1UH2rJ1l+3aLQVS4=-e%Gr#TgZ$3t!oc@+)k@<b(I9kx
(cpgjo!^KCx!{CZxoSjdOw(wQvd7h#E%J{&bX@IL|+=_Eh&Ol1LM=yRn^?{u5U=QU@fqksvcu9r3
HJ>eB<cHT9>>G21Yvwf|aKF0|KQ7p!Biku)T1hYI{WJJ<gb&sHo!vJ-tu!q8Xkps?<l9H4nq!{G(
NY+7}ZbG_%j5szP;dfL_P;U|HE?G~VrEHau9Y=Aj6xJ<s+WdJuTO}Wn59<&30d`Qx-L9^Lg=x*?m
Nj)x4AqH&1PHteurV4J-2V_&rNr)E62p(pG-P*vNfQ7BuQUJ)d9hd6pM@@`DXTi@i9%1BOISGXs`
qn&3|i@*<pMYiO9&+m11zAirMQn)04tSDJg){WzDboBPV->x;YVE>z^{u}fd-qFi@3rSM8pb~%V6
UfRowMORd(H40os-zwAV^dE!3%fTDP2?D779vjZye^P;}Z5hSJx!PSL&`VXq920dz*4ZikDcJhbE
RSp0HQ85$%M?EwTI4Vj8~qt$d8E^YF2L2M`$=m9avQTL0~$cuo`gh{^KFu$X|(CXn1Po!ya6Q{wX
kjDsTpif+K>W&{pJd%Fz2%rP6ZVrCA{{H>VfvtkUt%AjT@kH3_`JG2xHbd1uH)^6U4~6=6S{&$+n
ca4e1R$Xv>)&Xs1W<FV<^IX`C2TXQajwpSY)CRa+HTZ<xP6KHag^tAI7BfaNK}bqvqUs8sMe_8?H
V-Gesd__lzQx*3~<8sXy}mcXlNLf&Mb{(g^HMnPf-Ez2DppV;V0<5$6CU&{)Jz__9>ddGaS_yp8Z
I}l8zrWV{To+=Ai)%<FiX|xYA*}1{hr>^QKGG@}0q6;pMqGAbhcwifW*`{8r&VHfoM>KQM9?Cb(r
lG8I+Fq;n9Oy~!hx@Y&p5lOb9q&(M#ch3DLm2@j!#O9mx0krE;RjQxaEQ$fDIrJ{*ao93!iv|kXJ
atDrLxvD#}^{TGBD4)397wuM_WCn1H*Lj);u{7{-<KGx#FUm>!sP>-=XliCqqJgp&$y`)qx3Pv$h
}8@kvja96GL9~N{4-88ib<G6zM;nMS3-q%kgn-lXBu?!#SSxKB-Lq#hGf)=k}cUYjYoX`TwYvUh{
wlh14@GBrgI{iPucL?(5^9^lP2mBfBXqsy9=G83uXn2)kIMm7K7|if0xEyNhp<m3(e~Z(^ik|RZm
5y?Njm2OD;1<C1;kQz@(cxeECw7iJ}dMMo8T>j^>-971FMumaEx4s%`^%u5E^ac5@IVQ$Pu<S_}`
W^7K@pBuF&g*v*id;bBqt5zM-K#7YM_JWr1a==QN>Y_u{yXH)l(H<rhLTv?MB<!urQS)5U`Ck_uu
Oj6|1TZc)Sfe@3AXNdCXVu7~dO$=-b$~lW@4HMG>64h<@M4aA>6J8WV3bNNqKO+yI*cC5+zV0;0C
jdVl`wcORZf8J2R2_*0d<Y<xqGWm|PMcBE?3}=S?t=xj%`z2`bXNIE{JRI*<CB95daJBDC(?0X-8
t{J8)9|XWhtFM&d4!^KL;^v_JF;h$b^j#xf7VfGMI<-NV3%UT}T!V3r^$UHY1EhFog3(z7biR=Dy
R>DV;zSGTU^HD9_;Uw+9lZEohjpVOPkh$?0$pTVyX3y%bU$NfaEC6<{c5M}J`AG?#`LZWH9}_BzV
I#S@2ZnWnMFF!?+280wT0#Q7OVI&yeii_l7qhW&<EpOQ@E?0WWzDditJBemA#6!wd5#kaTG?>7gG
jKFmwz#Fgv)CYc-aJ)I-zVMM+HK<0Qp=t~y`{cMe&|P8~1Ex0zG&y`qALt1!Cq1H1_>5c{;0gZyq
uANQ<?ZPB<k-7Y8yMLp?~aIK$0mxm`pvO#VGnZZcUDowBYI0RH~QkA0zN{`E}*M-ix0c>@D?8);l
oi;a>OMK`oo%t;bfhAEZkc-2`Aw?Kjxi#cD*dvRq3$_6hU~;p2KwDC_$ot-=M2JMg52e?c5{AiWM
*}r-G#22D)W};LFZ&IdE+g>%5UJNy%!y*r1*zSy=dngDlhYWYNOCnRy<H<sCJAn7#bYy0``b1Par
56oL^G2oG_Ku!JT-G08WJ@XRTWavMOyVqdWV_zhT`p)-=#gdV$ozt<4GUb8bWp36p<IXMH$hwUMZ
`K*zC4kLit2$h~5Z=;8}e2*T9BUnvIEc7Fj87{y8wZFmQqkH~aF>mxO!)=Hqs5lME5&>aOC;?*0(
tM#cI9!nGCh*Ve6W^o<K#ezbBSz-~ztC)qHmJl{2FYy*BQ}|Hdb>8>-j{Uj(<$*8XhMKFJcQ!DJq
fMxi9hoC^hrBGnh7d4C~2K=B`Wky0USR;hxu<0ngc2hQ&L|#1HW8Fx-B^jyZjB6y1i3uqY$Gi+6d
ys3@K%w`yZ4`pm5q2PvK?7sEa0mJMDYkV_1*~VH6;@65)pq;m~6OcT_+d(D$)l(H-LG9vvOmb#z?
O(Xl^(LVcKF_xQM?&vA-U1%m9f*Ew+t)C@=g?hUY9wM*09)>j*r$9_L<%k_ssxc*2^)mOj(q_L;Y
8jd?gm9Aaou)0b#S=V6=);ijOH46aa0((`5&$tc6^_PxYJcz@bJgxfuZx(V18Uj9d_;d9RL1I5fv
>R8UoorOeRDBOc%tgEZ5!ZRqfxm<chlC3s3tTv4M8IzSJz7;QQtN-F)f(KX?WpLa``3mJaF#!AX>
4|3(8MFZVt`a=y`vBjcv#m3lE)(){kpmk$PytUy&PoULkt8afmSW?ksUc4R97X<7;ZG_iH*ChW+-
M)efj`fsKJk5_oz=@_(V<iwfyKE>Tx_C)C>fb&m%oi;4nsOJ!@1wQ{%2U-tQ?Er$>kEpx}wJ0Da1
pROZRQAOSSQT|<mxcx{_SnSXf$Tuq2~6tKINcu!q{U;(VoEsV*Ro)8^WvJkMuy;2&ZxPf3KK2u9(
+!L~0{E=?MWa#&R&6wT}_e(&oD7od^Ey&t`4UKKW(K3Zo89qquXMzs#E8r-wLw4){*@;_k29t@hr
x6D)+r%cLB{@;zMTbQc8p0m8mf}qu?0Gy3!;e*FEy=wp$rTk3{IRdO>;XPC3iTCdJt*^g1!0#B&w
?z-^JTGCHwQzOb5XD_x@+BrD9an~0O}6n7X9mDh(!jcTpD4+s3fHl>zR^E295gtQL$fSZ6){&q(b
B9Gg=|e-GH@}U#KZ{9Pli8qm*VYHO#<5Bb8v)0dceaUbiq95C-*ZUlw%Fy+?fqbKz~~nD8lnUEzI
}Hr;U{MajKys?|2K{;anCol}3N>pO(Kekd#IRy@GI_v!kMx`FaDEu8Y!h7F^E(+B#qE&vk%|9rX)
ft5hF#H&Te$1UjVw)i+wA6=CZDFG{t=hy09$|%TTH)g%!!j7lhy7WyJ)(5Rn3gKHUw&oA!q^}TgS
CTF*R@%DK(hj)t<?XhY<`eXnQuKhuE>UQT-Gb_V(ynqakE&t>3^v<Uj!P-v>Pu`Nkm>xsbx7L^=G
M}&w7k87gx>xoGrScDZ5NP1m97DtrznyZ<g$2ry4_xbO*~S)a3y(jlb964Y$Nf~Fx?<SGc-iKVmO
xD(Tt1^(WG*Dn9o`U^U@MZpH0(wQUQ9)a+8w`E%A;*tGoSLsofIwC}Z1AY7nrz_Vo?cm922C_D!$
G!i6Ty@)asigM@AmZs7c1hV1jtYKeT7t}^mVQd9?Bc@oQolNPw4++xU+Qr+B@qzJ}JxFF06jQBpB
M0vWjT{yEjurN@FZj)x;aiawRfPpf?1<8hQ+LDtFbO<1d<Bj;RN<OwMgOh_FPsPdc@gZ#s3nh%_8
VlgrZp&1_ntAfAE$tF5o~#$)I42d2ci079_6RKvx+C)HBF*4S`JXif6YKtVrW@Ps7spsd^&U*bBn
_FjpVOEh@C8OskB#m<ZD&Rv2+tTyLxZZJ2jyGH_BzPPD-V`uoGvGDfT0o|HF2ztr(GWAcnujCRlp
Z*Odzv)OI$-y)1U1tzM`#<nuy$vdxUH1A>mwu9{u=}pvzliS745qY#A-fNgDe&<c7&Ubkq{>jDd-
c!f5j91JONQ6+CFs(p*l~B!?9w(V%Ruu(v?S)Djlv?j~E`1GdOU&P0_wkN8m3@0@rQA}%bdyb89p
7}<ojjYZNUd2!_AsHzPGG9^#{esl0KLPsyWmYM5Iqwpo7hYQ3L<4q4|v=;|`bHMY$I{XP6!b#v0{
QJj#I)!3No$e_S<SF6<-~avGDc;d#lI=4@_VTl*NR^BU;&*p~b%%v<?=Kw(@s2YQ)yqaPAW$Y@-I
qvl<$075ak7Y~aYw<ud*hj&!wFs2#!|MEwU;%-VORS=ljXy>!KmzYm9>n5e4T!GIY}St3)<|2OD$
G+?voFAZODBnukt%jx$hkW$XuQh1wzqB!drSjJ4nM&u6~D7B@e9nJ-N*x7^`1@C0-)r3MXCCX|U@
V&#Wb0bA*KnUvfr$$MNZ*iZ5ba;NTVykGhScqpoIQSgFFQE;5!Q*^lpoO@^WwM+2B47qko&sdt-{
wrH-zoD->i&{|5zmS%^h7?uKiK>g6|GTZ>q9>hVZ#bvmNBer={9F+IpKNB8o4>UG+4^a)=J_fG+)
NhGPzU7^9BnpgkP?~Z&9>*(m(0-&M4*&(41CxP6`Va<5_O+M<%a5qu(wtp}*P)p&i;^TP4Kbt31R
Sv=g<okbBPpns(kZP*6WBEs*&~p5NOQL_bYuY56MeQ3IzN+-!#o-<Q`E|+m=GDlH<1xlf>A2lO#s
d<M>o%CuPCg<6^Uam(F;qvrecpM#->Ug3mk)%jex0%61rjJ1cG3TC|%&-dw)IUY+ltM@+ydW%MeP
2%LTCL!23XjT<YxRbp5Dv@(8)qW0C!~3d2vP?#^!Seg^A9szXMom1ws*omQ*e>K-9@L)uqj8jK4E
lqJT_(QfP(L$H$<xZ7C*!LB{CY(J+JI-gii?tFLEfGVom*pl;>=%{+XsG%yj2hCt8bZYB}C=_f3=
>bB)fdLa>J$g30w-v+Qke2vU_d(~xebPNrPu%&*aTI-c_f{u<p+%CfPRp;h^9ZtDF{*N##`v_V%H
J(q8oU6q-n;n)vl#jS+9KLF;&3O|z;fjlrh&UK?gUky$DI?q3Lys&2e-DOB`%pTCSsaccLPc)P70
pTabwX666D?Vmy)-OBHvhwHbJQbY#ioz%da$NN(`|2QYyySk7f8%ser^?^4*c!$t@xYG!~H`OGPB
~v55R=6!}8~?<;XW%|mu|jL{Diub4I*6&L!_MJz{pDt<@dRz{+$YR&eyYe>DX&ty~I^!Yl|WO5$P
)1|uUDIac8fLQ}GPZRX^+m9W$%h<Xg>9NYAwMMwTo(&DVtaLrpPF>QUtAzZAhb|RU;81A2)gRKg^
dlHfN9d?Jz1nL&O2rwP7iHv=etXc@l9M#_=x^4g6fXb8oOmfPS}+Ej%?iCfDm;b~l|6FXTLk&cR`
65cA>wGzlNYU|Tu<uFqC^L{W4@Iy6HLNvyo?qczls9iS*m_I-OogtwXnn1BwAtzp86h)GW=@{$#C
KsV+5~Bkkf@ET?IG3hs~lyDQ{o1hOR{+st)|xv&U*;*N}$8X#~f>(D!RQa-y237Q%Iu<(a34@A7R
F`VKFT7e%lOlDxx&?|GjAwall@Q#2$3w>6zr@P3nY44}oaw9t9no6ejqz@tSAV>*`hNq$5(?$WXE
hMQrBNb>&eqhB(5E)IYOvUiPiS;y4~6JVJ!4xq;k`hO^wH#{7#Hd!9dFV+!xH>aWuJb^?-NUDa5|
DC|tM|nCPQq(bw@kgPgq<)|A7-u;oR3Vhy50N#|CExi5$7sWD|NZLi8@tE*Wt2Ons{fC_|M%c8)2
TD@`yXX-N@FfJP%#>+-FI*wskWz{N&5yG;MF5Kunq>*8;M%{@7NdAfOP57nAlLdXPk;!LUd}teL?
XJ<p|BoyLgis`G<snmgq97A}rKBoSWovlBh3(zU9+aF;|Yq`CzH~RkLdebZw!qs;CWlka4WDM0!c
%KSp*Mm=?s$9ZgPcxN=xYUD?tIYCr=JbX0|n(^)GE!;fC+?y+1&c+U(sU%gQ<2gYc%SR#k%EgE9A
7-G~Mn-0CBSg;tclX;?FnyZC&!J%lG9HujyNs&ER<+Bv^Nk2o$29yuR%QOSg;2+Hi@FKIG8SfLLh
f)jDUq(jzl*$P+<fk3&Q+UC0PUfKonJg%rCEM#U45+%zNU=a$;u*&Ql~R8*$}pOw3}He6M^RCOya
IX;Rk-Is=bHuv{V2SxC9u#eaC5M>FMCR#1$1?QYJPQ{PnC7B0`z8k_j_^x#>x?uAEu)Z9wUZi!1N
-X(V)~)qEETWQp?~H9mCg{ELc%e!3$Dl#ef0<krwd>6T)-)(zoO*lagTDdic8izA0!896DA&+dxm
<MuDbIa5#IEcj7_oWLo^<J*gToWmIx0Rin}}lcVf4oO0U@^4o@bctOA05Qpy3;tU1jAMy_mLPoNH
2Kv#UA<VBBYNGt8J1_^#FZt4D1u*?G^<ctrzwgNgw1Th;hJJ%FRhf9vq<k2Sd}`q0Jb?E_*iNAED
C?-$tF80p?Fz5TzN0su!E2utQLPgl*ct;IY4(O`E>T&njNl$x!DKQFWYaKI4yKHAT!z1`qNTJ;;9
ZA!0UcEYS>D+q^^Q#jV>w)2R2}QI>Oa|Ep!qj|dh51T1V;iPZV?7_Kmz-Di*Z(9{esxvIUbDre4u
AUi^LK&!VI~woh_^u6c~+Ik8m2S;+zRZLyTuBV$hi<zuz2e_|K<p%$%MsE0|eqTXU@O)dFxGuuYx
|>)rF?umcvrNf;aEu#(2i<4DH3)>l@)&V;Hg`+$Zsa@?h^=nr<56<Q<3X}JtJmZCs@>Lv(Yi(-U^
T}{gh6ajXfT2W0cfL75=9!wP12ULU65;i_j4eX%^a2mw%u-fB?7#!qJuya!|k5jbyn9PzMugxqO<
~}tn<WA%zK$AxyN&@X#I${}`{mc#sfu$^Vn>v?4XUYt#x-eXd2%#?v(~(eB-5j{O5%i#W2xPR`J;
}JmGnfsvd8VdyhD5dwSsw^}gV~6|Ogy=Iesk~^U1|{Js|Ib}we~IbqqLX7B98bxEha`97QERA$Nr
&xcbj}isAi>p)@8NLu<g*i<TT}KmyMwLGIDNmkiMxQe~cBV9D~Icm|m4dOcV`^ipAqm>^!I}Z5Iy
MsZpHBe1oCtI*Z;!>d>XH6+1vkH)T4H=LIx9V0!V98eRjx=rH$Xi~>x;F*4WyRajF@<1f%c?GB*Y
26zg_O}%WGGiY#~GLNICaKB7*qJ^ruJcuKVSB9uC95R179OAh=9BMX`kLjD_pm6~5*%C<X5QZ|(_
DMc*!4;IJ+s~tPEe=oG>d>ZkSUw2QqYOCj+f}IUy*BZ+KtZ0bRX?Z5`iOYstuNbd@(FzjWt(^1c5
6gOBy7$Z#UGQ27V`U41?2|luW)seDCbD<%FKzU&Ap6JKMJXj9P?i=-+{b72lxh|v?Ww1d!*DcK<F
kpzj}UoiKP~+C5jb2>8XS}0ViR2`Df~~HXr~Lh~_lEU(yu__R?8Dj?pH|212q06R2Q_WO=3lt2!{
9po1-);z$S!F`6+<kne#L6ti@-L{SVap(@0pkjt5oy%?&api`vIKzn@l5$`QX(=R|Q6N`wV?vFNN
22J!7(so)5t7#e|jFt6XeWd_!ku*PdTjIfwR~PT!y?^`i^3}zI8~E=<dY@2$9~qUtsz{i9%u^{z9
aXk5CZ0gHaa>X4Z4$m%Mt5OFmnXZ5tL|Z?(Jn*)#W*dr3_MSjkc5MxF<;QivpeA-Fytlx84~2ro;
-AKk|(#TX!5iLI|vS9G{`@qs}*PmRqf$R@kmH6!q^t#TwqR?I4mCCBte{|c<ujVCL^kaYxHV}D6a
uQ2;J(kOf;LzG$n>I3xg#Z`qO#HD2FarbfYG~L<_iyQi{ALCQ&v{39q0XV3%XQSaY862;>M6Cck2
kqF)PM3*>1!fev*-86<;@iF8sBbfk_eA+Hm8WMz~9hVGB+-EXmR4P&DyXI25r%dK&$2$h%y<#l<$
(#CCxD>IT@lxdu<WMvG8{UYWHkMq!V#olrFVLwcHIBN=p9^mRd<47ToN+&NyLpoGu4Q(&HNu+CM!
%RIQU6$;eBkT_nDKenQ3o^qLfR$GC$1J#2UUy8@g-ia+tkPFRUN`^+(Ts+wq<4Q^TTgfoHPdAi(f
BF)*CP(#K9HMjYki5#FM7CHC#(6weu6I5IIXvAt&tN0*=PkNF5een^a+nrK5vC5rJbJYFP!+g=ID
dXPGqVU<vt?OL2(PP51&9!Pan~6A3ebhPuX~6Q%SrLmoNT_j3pW27-aOAEb2s$Cz+5Oex`&$jH0F
o6i0K|<8O+<Md?BWWTSn<$A>DIq)j3;S{2Q40aLsriO*Fz2A>9wBoZc_H!jOjbQ6XapGQ?gM2WLG
iI%d}V%OSdv$#zS(3j6*UnP^#G7dvmvk<ILCUt2NDpMZrE`&o*iq~}at|7O1L)?Zb20Y%F4Kh8Z<
yycJu#3|InGm{Uh#MNnpjE?K;KF3UQaB77*>VboyaKVRO(d7kTSk}$&__mh1Ts4DqZ^lUzEWk5iZ
huC;k`)GUS#4O?~lXQ=|eor5p2sz6DsB#k||+VXMZW@&9W$x%~p97yXkK(-@Lf^nSz<Q=OA`?d42
JEc=7Y~#ha_kw{I|&4REJ;z)6+2RGz>RU;W4ByCEP7r@H|`W)cn+^G0Qd!^LKdzEa4oQsvty=TCR
Q&MS9by>-j_mz#tC@&4lZFVA0Hw4PnQ;o>YkiJ#IKFJ)ZHtYDN#=Z~A@_4&`k7Z>lYe}F+9TDCdF
ZBHGwLqPH~boF)OMoCy(3B4Mc>y+0Pc!wd&s8K(ZnEz+&bA>TXUNlpND^q#E0iN{OO}mILuEZp>V
7X0<R#0j0Q)_}=X7I?+S`deUfj4z4J@Wz*MJg^^9rKyL&4g!-L1{B>$UA00B61s94M-atp{TZXda
CvrF@mfZeN+TlWz~Fb8R>w*h;p%9A`6z`(<%peHP%JCpll1(5nXL-l$}eC)B!R<9v%XtP|gBl(m%
*{T|-e)ErS<EsjqOBdQOTx=Zt~;Gnv$tC_NCi6`RaRu%m=^tmX}bIXJXN;`MUImTX1I2gP$b`mfV
8&WM>^FxRV2p_W!he*xDM%@`Lkfav@h;whSW&V5ocA))9d4^=!dTjDK+fdpy;hc@Rv)6wMMFojk5
65D@<S@q70-LimPw?Y;B&B1>avDk3bNFNFq(>^w0^f~?FYro<>(}0w%nuXAHu)D03xb`TiCBNNew
M=*Lx#Mwax}zH?PqvR?$N|~XWpo>%IEE3204@JZFtCA%q*Hye1P*Pok}l_&bUa3;DWe>c++2XCKE
}8UV&sxGge%AdNZ)qGjN(!mX?zMt_#FM`^ZQ8g&si8Ij?$R;JQTrj%}wJXJ}*;VeC(I>k*ZXb0YY
$@p6eVA5@WIoZAEah@wgx8h;%k`KrP^rmU)JN^Z3O>>>~>o?El8kqJ$>2yDKcEz2S-p=zK<DQW&P
9Y{)E_$82tcrESBHfLR<QMfjp@k3|!b)d5aZK`4U-M{hV%qx=2Nz;rBd*&|b_&!Z^DiL#a)X-1RE
s$wonRvqZ8^w#99O~Mr_7%~<PKs-kpECb+Elyzj?EsDcbdOzg(3ur<4BFN}phkdOj$mG$&lL*lwo
xA#G>#fJDCGMUE5a?wlSCX#JX07`m{#ZFAEZXm(|4T+kp*NwXNKb+9b{vW-sG5nwz?_oN6yP^eo*
<gRb&hT|bvg8{lf`=;8eHYLLe$dJGojhmDpw>u+kQDRQLz^^Ag#?{YyMFbQFlMMxW7+-t0el3^2G
Hkm_lmRMl5<Ifyi~8(eOik5usq<<aXruU+V0~<Dc*Akk6A5Pl7FjyaVmM8BNGP4+;Nmiayc}!A4J
MhGQnj6`-^S4c(*w*}4fh5G=`mc#Hx|BJWj^GVc2yFJJIgA=%9aqjaIz+mM&UwF8ZQMvhM6IkhFV
=0@foZ1L+%>cOY_j#!aAR)vjLa{a5zpDr*V$Q?$=_=udXF&vofcXHVBo|kIiS7s5>N{W|)e^m;;L
v-~?GV=d<IHe@Qw52+ay7Y!`kD#^OxIJQ0Fh`i6^IZ{nBI+vIiF8~q9O}xR5j8%4@C?~@bfv-TWC
3c4$y)*y=5gqR<BKW%XHtGC4c?rl6ACFRp!_KK7@@CuDPoz9@4UnuGEc-&uPQ8?OLwUzAWj1p$U#
W9iRT$bnBq?z{i&-zxlygE1*KyBRVX*=&$<Mn4+B`up-hZJu>s|vI<CMYB`3OELW0xYbC!$U$GMZ
!qq8fyf6G2D>4>aZ9LcE59~RX;Y;qV)%G|%ZBVmp2_+Z+y&#c3kg9o6NxkVp6z{mgP_1n#FgXZ+S
`Ev04=^uU*@lg%J8ahS&!FsLRWx85;9iJ9}!!={e6grb5>ZsYlUX8<X?(vCG!EDG-5UEyS5)~^{x
INDIP)GHotZhxR*olU!qTnj<FmlGD(3qo|l(;VS0FO-)Tx4xdwCFH$eYJv(+NEviE8dj6ksBKr*4
%A+2`;W^j~lB~_wAK8Byo$9Ju%K2*?)_8I<KVOkkBkbv#TD;9qhQpRyhp?c69e*ou1_!Qr<PL--?
_NG>%dZvW#kVdNzO9;2`uFUq`QItu3BG7uVdjWFQ=ldnb45f{;h!Vh298QKKH5m7t^<_&dlAJH?G
c#iLbi%yZm-O*&_Su?!+Kh4U2EDatN<kLi;z*}YiVL}s78CI@$O&>_~aVLJ<{>bGHz&M>O}U)&wK
&j%CjMPTq?%5SQ?F_gYi-Hcq#y^e)}Wz?$-5c_9@IeRhn*qNcGG1IWV99ybcL2mFrdCke13^SJIW
EHrFuJ<RVYX)EZ9-;A6dgY^<2)L>@Z?A{vKb>Enzb7?6pSG;F(>B>cAt4_LcGM8)sR0aTlCvQ?4$
(0cFDL{F$@DEYOUR&+tNA=wMp@|b^}=#!w)bRzN<wMcVN)!p7oy~S%B({QKxt~q$ZuOrgHoLADfv
T?y+NXIuSl$g8(Fyv_TV^DVLf8}3N^@nLhmS!<sW5h0|U1xAulglOp-P`lYX?u_AHqlDx$CBmNms
+p#|s{asB=KM|R2}%(NcFagXdzQkR0kP>?j(_+ebZCgAk-obiqyvATT0uRw}&4c+h1r~p&*P-R@c
b%3=RMl?Uwi~>H%j=!rwE%cQ5QgtUqJ?jkqV0Sd-`o;|m>{ivHV5_XSaqatfF~#$^&BH-eljN)?$
3YHzlJ*yLPP@&OB4d6f&h@r4TpCbA7%3G^lJbsZb8=H{R(cjjylwu%I#mH)=^x*-V}_h3I!RS~V<
3WkXS-k+eiy1W*Zo4OF;U@<$!_5<olJA|U;<hty+UZ7NX%I!Rkdrh*9Gkf!}Wr`SNmUl#!lJ})BR
Cd>W0eKCAN1!ew?`zh0-*D)UV(|N3EexmDe^{;X<#g?^>t}Amkrnn+5tyd`J;Q7k%_T<PEYQ*Es5
1W(bhwg7wyN&J7Co3NJ!JTe@}^W<<CRn@~ZJ$*13Zr9s#$+(yI9x5}88`bnIYqcqDH-kv?;Cbl`D
R>IzHj{`@^NC0b(np@rZ^{ckJGnb5_3}7&G<)+_uhO6&nTk{60CGQv(1;`7nKd|fT>pFY{R^8&M9
I6?j_bX-r=yF&?Y{Y8O6Vnhl5e$6;dmlr^wzX#x#ZIBTqG%n*92cU~I%!#JNmxl_pA$&)%Rel3OY
RKo#yQ=H3KEn!v>?QCC_0APDu3Ly^655x{|s2BJfJibo+%CC&qMZ{N4O%#;rohLESU<pBa@ZX?Gm
p_ugT9}j`ItuGJ$ObNG~|GmcFMGEN|~DhlZUOcFbJ9=G7hL6Kwhbx5R%&q|#LaiSks`9;>3x6b&e
g_w(Rf3FE2l)>^os>1K9a2U2dGhzHAC)ZzV4^U}+X2ypVANlH@<fV)DzRN7ypOQ&Y|k);N9TDef|
7#C(b+d3%SH!Yp&w9<cV=XD|O3sx=X28TSM{rcSZHq!R1I))>i_Mjt=xt*;i@uvFfl^#1X?jRBX{
w?9Xbi3Q<ZkFYjXSw4^wvBI#Mvi;lt|61(9uANa<3wbuQq)@mq{5qTSG&s1Z#T5d9)P>rMyuH#U{
-@?CkImDe->zzr-nJ!Xi2dLP1gv^uYc!FE+l16zDvFop)s8tpXDQ_)`kz6drw1ZHVsp=bl<}iGer
S2DiMJrG%cx4h)c6Xr2*73z4Db1`i53Y+wa6=sMKYUS7}N&n~A})uVVBpTY}k(8k1|I(063yy&}g
wpn!&Du2!v;9SLNKnr_O;S>y|KZ9)1&QYHxLmdb=Flh+VfpbBamDmm{Xkdh6F#gED^__gi4lVS2?
hIH*QD~gfL+2v!EuwzrBwynZ<iB?1UN<S@kE_sNf@|xR`JmtfeWYAZ7D2Dt40R4fwsw5Y~XC0<aV
l1Cha9fp_7I&V5I_lO*vSU#ZcZBdB03Sm=E4^Qhdeir7rl+C-WHWU?lbkYXd*CO-VUh41zq{5ziV
Xm)yG3G&C~hll5ltw8@+;c8xd7=lhv`Q%<Z1OaFSDv1Vr>JY1;9p<bVx&}Ye@~i+>&BF>FR)Kfd{
eM38)3V4JEbEw*%2}2BiU%fkA#S$vF})b~6W<jXn(7^WuzMOXzLev;b_wmBI$(SfEP8LzdizXG)>
s+Nv5nGIXj&B&<~amaPGnnP$6Pi(>~>jZY4~S`=X{0hYtx--s)5i*E!VjbUXtEwYdPAjRv7MvW+6
rYDG$W~9p%u6mVEs$AWNXJ)kU?ZZ{g;rZ_s#>z?<IpzX00Fvd3BGI>O=ps$Z1KT#CO@SQ6$lrJ16
+Qu@I%B_+r<31vbd}OvZCRDg6lFEI8(ovHS3OqOtDdib*PB02<8*nA+*Z%L=%eBjqdIRqOVbQXG~
5=IR|o8wdl85^uoclF4mR>41>ZB|fHw4$qVolF6(iVf4sRn+KPc$s5yji*dtAj}D3Go|y<mVbedm
h+vjG>kAKfH`Dc-*)`tv*MUs)^cC}~RyWG70JiqA`z5#|d%=^ktKF7=>}xrIz>tX9XcliMdTT{^K
eQbv$P(p)Q~tSXVn)TyS%pt4{=bSSE0L4v9ZGgV?$$)v6jT_c1d)!U=8ijtdqCAVOz!xL!L%s^XO
^fK{-L3L?ufhnzOWqIjsK4y!PSx+netEa>`q2hkxWwxqf+5qG#BP&befw(1<JaBp_<5s@^qk<xq)
yRhHP*zKZt9cL0ZwKCoxy$Vs9EoM=HwE+ZmB9Cf4qqilV@KvqQ>*@z+K)3RSE>1|Q2wZ_FK)#1U@
L<eZEDBG`?D`0&N_C!y!9aC3Bds&XIYaVPct=TDA%MckhaIO60%6`tJL`8NwP{lCh2`rIsRy>TQc
oAbr}l_zO5P^>JLlq#jiVz>v&IH44zBgy~H?IkqLv9b}(##8*#fOUUCFRpLHo5`Py0w)g9#0U{q;
12wyPH6~ozuS-jaLYSB$XK&^%3FSnu=^Ub_kRmX}E*cHE4d;e*E?}0dOw<*ir)?g{hm7>*Z84eWO
hQ@#*N`qr-Q35^DOZnM09WYx@b^}+ZA=j%~5Exj^NWrY9AYm)}tLc`M((LP@8lMU-P7#vrQLjp@9
Yt}(E61Mhp&?6gY@H-O>u3m;1ac$%57S6>9Wd97s%Nf6L(bB7>I)s6BxCYVo;Zw3d~1~+(7jaYa$
=$bUE|{GrBtU;5IEn+(#`yRuPR6irZ!TySx7%B3$r}MpG|`}c4jm*Usw(~IsmVhP9qh~S5ixTLi-
%L1Q|EKW?--1N#J@0hw2kRuJkKrJ|#QqSH^FdFB<A>ZNi8R$S5jW3z~=>|EYFQ?=V%()txvrn7LR
k+V6GRgIW=nl_?5wDoD9QCiDO>Azgb*vp^R}mLx30pkWFzix!&bmTT)LB(NyZztSn-7gL*XW)Gyd
m-ebS_iX!FyFf1H%@6mDbc6RPL%giWA#XV5P5f!ik#5*c=+!@d7KJlGl!Bnb*CpB2HI7DeG;DqZQ
3z^IT4Tx=k#Wcr3Qfmz#xfje0lk5pD0399E7K;>mVBK=d=Xh*Vo|ObYA_@>-6W^tKcZ)X{4>xoAM
?%98`0@<gmspRIQ%yteMb3J^n75leoI`>I2c=Slfbg%v*{`pd=Y#qb?%cDss4)@KU#-L6yRKuHs7
vdm?aF4ggv|`pTiPhPK~=Dre{E>atvS-=jiQn*rj3L1G!A^2`<kt5sG;sk_Fg|5@*UxbL6PeIcbg
}3_5_xyPKSg72}^^e2aOSLBE)AD4GIY0+Dk>rod&EbMT9~l;Y;WhG0c~6r<3$<X^r&e|<5$y8Ool
Ui|JpJ~_QfUSGZ$zCOQxj(5SkH_4kHUk{)Ea8CEtyT>Q|;NAPn*XQql8NRxB^ZoS?`06pgxVm`$_
RS0XRrl!In*_dIpFevAot?kDxc&tmpB&vJKm7ReC3N=lv&(BN*@5QYy}!7Ae{q3NuYP&`?CmRRqF
ub8W@LpEyt;n*ru4kir5<4brN`&5F28?s@xprkm{ta(pk4p+?qYcP<|ioif^~Vt<DV|xKRds^e9f
^!i|4XM23PU;$2ZU4zJ@_xUC}$*ukYSoU0z?leKWjz^_F_}F#Qf@k2*Ype<$$ov>}e*`!PH}f$!g
*q60fT=zfb=11^5Pet$lc!}f~o;0;Vai;39j=a7Dm=;xSzPUz<`{hZ>DdkB2nz@JWA{_DtpUHR`&
{yUQYj^)1-dA~tf)rX^16i<dK$I}pnY<)|Z{TI&!dXs&F6DstiMo7^P&($KAA!dMykPzE9rtn4i9
tf#E?O1PNTogY%sVPtIDQCOYQH9i_YIGhO85eMN{fM#x&_`?zbG^gK|Ktf*v1xh^Y(?m)SRxjFJU
hR_Em;jtE<29VcJk`enjBR<o!p>sWymtKBv78r@-cmV^{gplf3dBRa$aqtI|0QkLR%b#(2a_l+uS
Z;z%WXpd^q&bbHR3PWvysDZAHm~43v}++kOR8wO5Xw!ia`4PiN)JY#4{r+*H2fP>M7cSk4KJu6uj
J#veT{SH2pN6+pf1t9k=h+bf$Z3!^G4gq0MMP8*mHaN`u5AP&(yEDu6fK;Ea~Q@Bi3LNK<wVRp0X
c{JU5phmn~8A?$j4S6}>>BlP~HB^4Zn%L7)Oo<6?a!!;vJsfb4+6so1nMX#Qt*@nS*&ES5I`zdrp
}}nk;<=ChDagwht7CrDCZ+;yI>_VKrbu;=>>;01#l*t|!*ol0Pq3gl_xl;T#W-y|;c~qS95TS@o4
qVBqIpdp$dux<DrvY_D(8s{q^D0MaJYGUY3D#2>Uyu(p~Z-vB45EAYiU`YNHFXP_~scGcad)Exa8
ufIawLS2)7Ze?pwJKG->ypgx*~V^=B}tY%`amnbnQNWO>XkH*>U~wD{;KhBj;Q0PIkySo$dzPvBF
@?nXhpI|a6@HXJh#AtoA3t8`q@#?z;DYF6r@TJcgzWDqoSOv}6s;D~{Dc+xCa)oMUIeQ@~DPYGlG
E-2DCp;NnJXtenOHZb)L(TOOpo&Z7*$)yCi|1X(|y{6Hiaws(1nw6|EU7F}QYr!=7P<K$qQFv-$X
>ebC8kz*bNhqe6haY&}z1nl0hF`Y{V-C(iY@bIZfh}?*0(bk_%%aCklq44qxjSSc-D>>ej0?E$m_
{lpV(-rRB1c_4-C!}HMjTiPWX$)VE5eY2=nka~5SS{$V3P4#+#H8hqm*J{a+}XGBk?GRpfN==u`c
Y8f?Lj{n3nNQ&ZL-@k)eS4P%q;!aadIKhQ3&7aBbd--m5#x1@w($8<t<bHp*fSKvTU-7E36ZtmYP
v&r^5^`?Mm`GHwc8nC4!!Ls``WlO_DeRDZIgnr&2V?q-+;Q%+4=p-N`%N6of!7+B`10fjnp!W&KE
SUJ#ymH$k2=+_#vkgDLw>8=Lu^{QetwK7wx7f(`oTdqopm8hMM<sa@iN0}=J?KF&5+?mL;ZbR48n
E^1HBT@u!M`^4!G#v^KvSB0ue#u;h``T=h`28o$z*XS6`^vy@+5ny7otUlBx*;s(#{VIRu5k72uO
e%)V>s()H9Al62CjwC2&`uLm?+H_T9-%k)&qL?K$WM}M$6^2Woo;YWfekh={Jyf=oF43g4CBr>oj
7)-qYG|YQ;VZ%w4pjD5X}}ySSn;#$@ZOm=LKp%o^xpwqFlE-1HLByv{M8526)`Yn?6dt08=!i(%W
BU=Jd^_57$O!?NEJDK7CQ@N_c@hs3~?_>?N%#`R1l9-FuvzwE(>_jY19+u9u0h5h81ujuy--egb(
zY_aA3MN9c(8PZn_!Tm+8n8NG6c@_*ahAQU+NOq7bPtinG~}(HA=6L49Lft23aGwO1;2JXyYwb2k
meTBM#7aj)oDq2A~`kGzIl#=8@-o3%fx4N%ou~IEG%=U2Fqo@D{eMY(>~x)QlUE|gUZ&I70+c>*z
ya_dRjnt1sAOhT57$|vMa2ON)OqVGbDpZ33(Z|<i-Y)ki4Z*p&O(UdR*17@rDX6k!t`bX)W_GX45
e*R=ctQg+~kPh79N5kl}||VcP@xCKfgUGl?i3y4pCP3>a1FObKOP*<{iXC2NU`7YH+_ox;@f5LNI
XUY&wKQ?jr4m8(9iXsm1vBF4zI%(x9wo??QaY7E9vvfEf1D!g7gRQgX!O_Nc+xjSdauNBS568^4D
PT9C5^5A_26!xcadY@GgFKn>C##7*~M8wxPZ#CS1!^mUN7z1Rd6JrKsIUK67$!vN5U86^Rn3_RTe
6o5)n~AIHxucWy@g8b1Y*nrbIo>vuof6Y)yP<*B1+&;~`&H^uiT!l`5VSRsWv}BSzxsev^{NlL%7
aQ)DXp^VRP7*AZ$wk+SIj;em^<Zw1rm3U*dqCwt`K4RPe)_CM#BVv$QkLU(v&U5qnc;gcj^;eYk6
F8N^h#52pD^`Q$*d=F->dLq~4brr%M6OVm-Li{RVf8gX^~cyGQr!exvKufbLWGPpzD#tgfUHUH@M
Ki93HU-_Px1s~FmjE(_`*^=ia~NCF~*Txh0__??ng?rjo^pPx(L4|W;pQG^c6or1t8UyBCcY2{wf
$Daa1im^<`gv7FC^5Z|hc_xemestrM95tkmhq^9I9x5Duh%Wk4q{$^2?<~cF^!T9IMeM+Wx7Gp->
B9t|aM@_6h{z#@#8m7<kQjcJSmFnhv(B^@00{c)G)cdQfqhK|W64He@dz+gu8xOfH^>YikDpR5uY
++OZy0jydR0<emY7}@nWT<aG+D}r=E_zpsEwE>Y$Y>sp@cxPB%@Di8+ZAVY{5z6YwInW;rL{9-lB
(YQJ~i9rblRLp=_4lW#HX%b`kUX*kq_Ubgu+N9vTJcFr0iInoKs9DrtSgQ?#{Ma4G8BvnULkJd7v
Bkg9Kjxm<m(+JaLesO4fG>_J<Woxjx^rm9*$squIIuxHt7(ZGvHpK*dls1G%jZ287jrV<$^=}b0R
EJF#n=7##43NvCpY+AeQiP3P?Ei<#%+E(1L621-dbdsuChHUxJY_wStOsfo&Mte^y7gWu=Bm{0*|
7lt5Gvz+ZWeZ{Gm4(Q^mle6Cm1UGs=C&FHD+{0wx*hue5-dL5JswS)8I4bCuy~6cUTVxmmn}<zcm
GS?bq!H=#M`zGyOvruyF>qqhu+76k2>9@uXROO5>q}7_Fvm7imBSF7G3r-TcbFmr0QzDTeTkw32#
cAAveSB@yVa53Dp|H)GxTo5P$1ZYFKEQYd>IA0s`CE0}2X*Ofj$DUSFIJwjD8B6+%TorM-YBcMb!
-QlGMGDNM1mtSqjnO)}5kbaEFh{5%-wo^hubj(vLqoT^Djo6b%|bvvnIDJm;e`XZK`HZ&WRc~z%^
E2MS0{?47%=5XOH^vah`V$e;$-8-T<k?gd&$KLK#w{z4x{k(R%)$N@2I^BI5s*x$T?p_%R6>!oBj
$xT(KsXtqzU!>=aH?b^be*RL-%)3GFWN84R=6=0{7dspSE^wJ-2>FBv5WQjGKZ#lde@J(;LnQkPq
*$(x{VUDd+QDjh@!OHiL%w;lj2a>K_8gi?7OTdp3P>9dk`7ZqEc_+EW@?AvuwTHz7m?ypq~A<D*1
R;uyj@ne-{<EId(wbZ0)S7es3phQ#zaIJo+<?jU0%yH)GtukaJ7soOnY}%UdZ~2}TdMW2rH2e^01
Gi~3eg9V1NW6;o;|Yl)sdtxEH50y9qcIv{yO+IA-ol=?c%2FS)c`<%YZPNQVvYpX|{f8pr5dyTHU
Wpv#yJ-V$2n|*~uFCzL%pRm!OxaZTySA!kHLs8ATJHoX<)b7?fSJ%0}(6DeMg%aVf$xwE~;&6}Rd
QNk^KI4c^+)z^-`eYsTKWBng!`n8w6qY`#aY9KR-5vtMmZ9(zKdbM89ouWSx#suwKE-j{%s*?N%(
oFcbq-j^sZBSZnyS*z74<mZ%Q9fYr&6ZkZO9tNQQtQSv)s|kmX%blLdG2T9tWrd(bG~dyARK*2Kd
{bIY1dovb9mTNpaJYVPNN>`9V)xR&Ra=%;aP~eAXK8Jp-vL-!+45ITmM@I=)$_=d#B9L`3@#J!H^
6>@LUr^oJdMbOkSqh&s>{=)-IV`_(55-_5$3VA{X*hdmhG0{A;955p$f6E=SZE}sFD{oxVqfW;ns
0)vT0*R;0V{}X`Q=JjjHRr^ujD(TIxxl`ibqDJ^4YBRRA?tA!DO=!F9?kKcX;ca?Ug$y*Zhr-on@
33+huxnSrtQP<Oobt!i<vgiHePRgCL~}c=(8h}epH}K<K1XjQk0`t<7RcaxwP#bEJ_u`91gt8dK(
l0g17>uqy{|M}_K8qusp;4tD7a=;0sI=pZ8iDXt*fnR?(d>=ytO^!rfOB)a!kra*;?t8pdim0e$~
UYmE2lza?HZEX;vA{DeMMElF6!q)f86wes7u?<axU2!SEkKwLx`2&XCd?Psx|GV)IR^_vCoBWUm0
r*jpkbg{`|{s^#*09!+4ra%6Q^9ic%v+eyvgGud*6VDvzO^ZMd+%MO)u+<q2q*Tw~-3=iT81vvdy
bLe4gwWEP=YQq~MBk9tNdt5P*rX1yyGu_z}4fn10Ver0`s?t=GMQ48b>?tB5=^50MhoXMz93)gzq
SG*L<*A(a(dSN)*72z329sW(<2nZg85Y3U8hbgcS(U4Hl3fK4t~m!=8_KM}Q`cAt@A}f2rl*{09t
u(|7rpg+$)HqiC?}azc)BWYp3>XG@u*4fD(af97xmQ3AVcMyP<6JPo$V0Tw%<4~n>8;U?A5A!Q=!
Het3vZq<|L>j9SV7>(!v~+?@!y_TPioDaw=m_r_9qasfszAwbz|C{AcI%W4AlkH8JZ6&+%)dn<Tz
i1eDvI($-BlgP@tg5^dtL1!LsyT$5B5(i6<nJcwmXI-=lYhip)%6pxLH`^t}wTm_-HbQ<(VoDtTT
Em=gFgZ3y`T7&!W&0G|PJDG1LLznZm`*wWv9-gUTv@D-ctF|3kXZy-|d`-x@q~fmMsj+<M+imCw{
w_RQWnei3l~%yG9i$UdiUsCCqOfE4sa_d5cm-+eGE)tp?b}VJbEM&HYPw0vlKhrq!7ZcPA&1B`BE
r3oZj0<Xb~+6>7CCR`4?&!Y=NBUT7{+0qCd9<Nd?$kCoP)r<UnQAJruPhbrsO@p{yLH$n@#jOy`>
Cl@MW>dXV8c_9C(TW`hNY@Z*fRD%H0k_D`LgrKvIlGq(&oiCS|i|A%m-RzHN>$Jq7d}E!v%5f4xc
IgJjgOz~N(6fH3RVU)d$Uxd@jSq>$z#-ccesPU=UApJYg$`AvfD1eCh)*IzZzuocdZF%OWN-Uyi^
s>y-xFkRSpn8IluE^lSPan5R5B=?-6A8nMYM5Q!pis+xvV~p{MI|LJXU}R2=)AW%ez)>7wigec^a
N|?anvT}=7Gd=@J4ClW%rU<CI_Dspv~DWv2&J|OGE9&tep`W@kCF7m>nO|cE$49`W2#Mx5{M}dF*
%i<iChZUenrw$c+ZQ1p{ytkIR_QxxPTNUnN~IU7$)3o&UwW-0_oQotQ}NRF-0-30wtiz@VZ78CNc
mX5qDs2(1J#VB9#r6Cir6(+^UmCW8<hE2b)dquh<dICZZvVb{S?b8qXrk>nb+_gWU9r?l+sjVcZ<
RFTy5SV1O@h1);Iqa6(^`v<b_kKEmqoM?9r5rPIKS-xtj(d?5vXRbN2ZoarwZ&_I67HknanwAkDv
1YazVk%KcKU;RXxh&c1wwZb|Io45ktEII5V?Y32dL5x7SX!A!ZgjuLCBT~E7K5QSIiaGhgV}SLqF
e_#tI<3<~fr(~rSL8@ftAC=JfQ61ZcrAXTFxs#nc<rSPOZUV1tGB}+-&|f_4c}e7AHK#*ZfHbnLv
P}dIBY?WDlIVH#u*W50P>$M89^Jk5fv?>O^=Xmi61f0q{_WCg)xvrJnl5;^~J@@x9?vMpS^u^L2>
ugsZQiXEW-FM$~e9?KgkwR5|$ox%qK~RI)LK)jIyOQ?3QCOj)S{s99xaWVzmIu1bAdWh0%wlhq$*
&?Jg_ZT~@ZctZH{z-ENHJ@pfj9U>pDma0W_gw%jq5>Ml!lmqlIUWT*UB>I}v_SacOTYvISf`q1Kp
*_eL|L+d^io!$UXc78zjnq^6rj8uLYo%Q8+BTBQCI*T%7M7KJ?J#BOI8>OD>ajDyIQjsqJYK+!8q
bGd*Fwe}dDs2L`C}Tp?bPE1j>U-%SN3^4aU}hjPPTW91p>lRese2igm>?u4+92rA-1sBTi$BS9dX
$lk2Ir~}8E$=Sw%_dy23FS;f4~t8_&Ej9v{b4*?lU2izcHXH`;t%`l&{`e9dx#Lz@V?`fL?x92PG
lYEv7E|Qx^qN!*PdcQShMB5gldN;6AL#K*d5<Wr~^<mUftp!=wnk3FN+&F0$7BoQ>TWsXtwA@D5f
EXL;tWGU*jsq)?KZi$byw@u-mbU^t-<>9;d0c_yDr=Tw2yRAR90a7+;f1I@Rg!i4!5kn)#!Lep5Q
<Qqybg!u?}=g5&@RNIzL5S%q~(XBWd0bPs2tc4PToJSlbAJ1qVDFC|8&n4rK_skG6_@u>?q2y6?9
8YDY#3HJ@Dk29FOeR)7JgmSaSOGzP$Y#^_bziG!DZzHNiYl5~>qE?t(N2r35(($NGYjr)7-31-M%
H<Y*Gp!tLY`0#zl9+6jP4AXnqZ*<{FjTUG_hE!Kt5tUhH&@<n7&t5(>I?hz_|;KEoGGfJbnNA{QA
fD7p2WEhho&ShN!Yof0@Lznpw`&oHeh@9B7fA#NK8Xw7=x(#Mwln#AcRBcTl7@C~FaDd(~${sm(3
0U)Cz5V5ESsTfsp|+Eq+#`#!dlQGHGl12eG$B{ZP@&&9MNVwJd?w20DQjGd$N>yxo>MLgjJII|=9
%QPsIC+K%0Hxs5RaEiLQW+a4JB;z6~?YFN9Vkyr}MItv0FIT_9&;*<Zi#QmE(8D8~7ZlCHg%eTVS
!ryw9L)+dRH|GnJh=w-ui9dKcz_pJG1`8yG%Q=qg1b;C(btrnR6Ks{z^B*_-nLcIna)&-Y^+z16c
%zQ!;XotBNP!rneb1a8;am?8OrrVsoMe282*uxswT2Y5Np%n42CtN9N-{VEo2rkPF2ssFi7vIYR$
-8hLU)&4(S&1M&GjyxB<y)!m{5l)0|Wu^H%9x$GjFi5)V&VoZK1jnIdt}F9;);=zXx97|+yBSaOc
ZzDZOoh^z}9_pFk~3xjk}q_5<>i#r<ULDW+1*B4hm00(Ab6i*tc;DbzN+q7_JpL}1;%JTLg6ou8z
Go8%>7l~(#&m&3_s<K(&n0azC9~clk{9a_zk$A|33Pi-thWyauKb#xU$<EHN%8X8tn@wiCP=k1CI
qNC}VQ9kE#v^+O@~x+n9KX1@x_EW*{JNAQ*IAj;NF*)Ot0Wu89pspOOy=P(3h#%MSWmMJIFviweB
4F9J*b@kEs@c3fmeI=p|KITu1UE=e%?y>Ry7GW=5v~5>7`y@EK{tnMGZ`jM{$_LSqK7e?r_hhrWG
||m`;pUDj6S!R%Ws93cVn*h@Y@9=}~m-f=g;?iWI5&iCfqJMKCMk%S<%a{Pq*PZHcS2pj}AHpmlD
~TQ|f8LpzA(Q{jE0zzrLpLKFZO3<5h|F-#5p5L>+SG@T%=B=t(1rYeu3$&Q$~1RUQoS`R@sizl3F
wenT#67vv6`9=qRk$G~>3Iz){4`h<ozK1(GTm#0mU=GEXwfSYk+ngV$Eud+@z}}~UlR=2lLJ_Kab
}B_vBEhuZ<z$WwU~D=t5(zP8kbmWRdwC4|PL0cCFSr1xqOwp-d?Tt9XTEqu9dMzB=!8w>hcS;P!!
>y)<A5;+FLiEq{E!D%^$r{Ew%SEgo1&@CmZmy8nkp8fQ2^powD7ETX{fr!V(2x+fk=q9(LbIh>H~
lXat$Hhb=12}@vg=)UaXH=3SGrO$<}HCXsF$!BrlYqhCk;W^Ptt4n%jmHp&l>jgVy1+bgmf~&N+4
WS@VV*ng8WPm?o)7*(pwnZE!ZhF>s3)STHj^i*K$qlytIM1xw@vwV*hUDE4t_RZT%O)Dm4(>!_If
qreVo&Zx;Go3y~TOo)$KN_aQ*yQQF0+)rOu7*H+({5GSzx+%buvhI0)gPX<iThDE=Nj2F+9xxD-X
i9k?km1AjC)$kA!?Z(EkutJUvF<<BFFgkxiiMjjjyu`~YSBTuK)wDr<jukPFXh52J#C!wT|>;G*<
}4UZw<a*mHmbqLoC$NPgZasPE4jp7JP!F>)SGq#J$Vb{g&w;$_g+^VcV^CgGh4+KRC4}Y3|WDkQC
`Y9eC(Egu+13czWN+e*B_y1uxt)Hdmk)62<muyu!>N*;&`wH4?7ko;Ep};ey*BO0wKC5T*jynmCr
~9}vkDpM(ZN%^EyI41)3IMr)X^EK>(Hn)%|eiT2xxY7ui!+4f*q6iFMil<lK{wwX{UK*`8464IpD
@fdE2F$K-TImUuP``siO=SIrrL|PM<>3zm#y<1@6SSHGF>+-NOxkZ+%q=Kn12t^H9lATf9rZW-4u
su~szC#oBf=Eq5!K6&m%O}f_i?ovP-or9y#K~J4Lh3-LyWPduxCdUL+$wk)ed3w9k_ZpaWc&YC9D
GLjr7;=tK-49%$+L-tJRSGh$x>c%&P6rnMv0s&sJ2+K<-19jKZcvLIGB$n0r|f4=r<hGe!o}jh=G
|#=aR&5z)&I$WVcJFn2jI|Fzy!9$Vm!YJHW9ke8I%yi0puw9V45LdX4NM&!9tAMI;dl48$cJ!3mG
K2WYOv8?6f_02>1}U2eD&<#Z#zp)!^`Cn2)aYTLA)M^h^7(0Rr|(oGL2>wI6XKAU@V1CMw>DDu9)
c=zi3`Gw)oYa-bqSn{oHwO4BSbS^oJcs-07Hn&di5$6<Vl)~v3k$;iZsC;bfCy<QP7(iA>eZZNi!
gbn{QeSE0%ytpG!ukT_yC!TU=FE>}t_o#q+PnT2WtxC(lAdSsKnT~QnEC)aqvlvJ^;Jybq|b{~AQ
fI5h%|FFc5_N<vTLVl+zQt=7o~_^!5QpgEe7h?BXQ<;U9ZP%gIsN59CkG&*|wN+iNP3d4!-;9tFO
cl7w0c7-V6B1TA9;syUm~I^-mY?uP)!dDc(OeUcPzz;^K;58QNSz|Arn)n5;lnM`pZYP*&bKh5iI
4X+WlF@|zYDdBsi2;$%H;8aBWg2l#T>ErU8B194V{AG+28UCYB|5~Y^XgFvQqtt3VO5<h62Ot=4H
40pnIsRcCjz)~GHgl*N3Kw!F$(lPzr$iJT)3XW63LiBed|9+Bx@3kVBR{UYH<gkk`-d~=-vX^d-Q
;&jpsIe3;HMi7b$-VR4Y5kPJPggGJ`vcC?OKVr>+HBwm-NUwU#36P(A}p5q1EkgcqOU?PX|K<BO0
{Uus1_W6;@6kY4MhGNmVpid4YJ?qE2D0Y-xb@OzPgNs#n1eqRMr3f`ijhj%zPz4V<gQX$qY9C63<
f}q11Pi1C2KI>aC`{7e4QxNRXbzgaljw_Qv7*(DMrxhl}jXG7bJJgQaHhZ^A3_TE<qDqtfNgfy+t
Rr?gvD&MW$4U9sYm+~ndsk5~6zDsv1x=<^%;J=lIF)<O$8F3J7EPBYrU_eK|fV_UP!kmk;=1^r%k
P%?C>`8XVnG0i>;XFMU`2?uT@N<61kdCUpZt!Yc!s7UHlPoc?vXJDGWWMgeUINCr8<&zFS>G;TI7
uAinIu*R1Yz;(1*-DAgbErmp7e${~RKJS26Rx(DvJ43_fB4i;$hFp=Hu{rG)ZNpst&hC6mTP26wj
DJ)x@KobO$9B@sw$w#2j)VNp1(rn+gjbR4L~XX?Ihv&#zB!4g+V8?0bSX!HYPM@mv&EKdnHzP2wW
5(n$T`*V~)7OE682^R-674>Vv_dm(Gi8I6L2b|EhxXS)}pimQC&@=*V}OWwB2eS_YQyTlf$d`w5x
7N_p0)3U0T<-L_~L5J*NzxU>?18Lc$Su{Fz^g3*3bX4l!%2V3g%@AhDzjx#>q_q)JevTKzZ=2`q}
TPGJey9bM5FxU&kfr~dUc=i1{zlnRtZz9OXQAE%1q5@iiB?nmNOTiCX<XMi%>(LRJ`5GD!s`2GhO
UcbPYqHHsyJ`bh5Dt4Z)$VJd-SHnqXs$cGzd%!JvuGI*B{saBt3B*eO1_-2n`7oVo-+KhFC9e(Rb
DdeQH~m}1W7S_-~;zGCIA1b`$=6bixvKU@=<g<EWFiB7e03+zVe!tn)Wl-=gMfxo|7t3nhPxTER8
4VZC{ArxX?9ymuJN7uyOLil5yD<(>2#v$mmtVToDi)z3yv4fo`pXVs==zG^^5$5cXB;DPJbjg@F7
8G@Grw1h7&uAl99pmE66GQAwwkfem(gT7f?rUkJ8k&>m_9Pu9Y`l@pkc(HZ&k0uMtTKEw25;RebA
z_on~gLr>*?rG}V7-)ai7dt}bot7inxXmy=OHZ{G2#k&okYPO^`U8#9l&=pc2Ou;O2c(g{=UXUrS
43p9bOpTjNXZfO@XT<AD7?2=UxI)yfh-u2vzBMMU`5iEo4vzH3WmQ{5%zSJh5Qy;`<9-4CIZ^Rkl
3M|`f;;~^ME~bj1Eg~WP2rUX|gFTx4t}6^7+&F=;3QP0<EEwc2U0Q^OOe#O0s);r7K)LFtr1Q>sV
EWcLgkIK>S>d#{g$Gl;Gm2@*N^vYcd8XC%sI~$kYr=KMHomf+FNbK^A=Uq#zSXkZgF<WO=$+;0G9
HdJjC?(Xp6ohX-zNE-yWyWtML#p;rT8Baj68hS3Kz`)-q1;XRWi#M8}mCyrz34iKz8!xLds;Z@{_
s1>eAwWk}LQNb$C&wz*Y9pfhqjfRW_MM9Y_!^x37At1P{n4<0oFG@)Npw)#_utBabM18EeQwkh(-
oxc@sJ7i8w;F%shleI2(ZY5HmcNhm+^KS(D##gQ7b$3{`wG`eYG^0ZYJ2f;r3PJLG80;$El<63>`
KMPDmh1Tjbi^vn}D2Rl*oELclM^E75lHN7U){pu*$8sOzD9Gq&+f}qmx(C{E}l~7TkryAR8jPgPw
(jdtuR?#qnW<iK0VRnKD_~GT99GK{1VN5l5)uF0+djp0s7M;`<hbKnFt&628^p;DVu#cbB%FpWF%
a2U&}H1IXa~TtC}_C83)v?&0w#o%yO!ry?|i=ApJ1+t;1XHomyCkO1b(1TbH(I?4!P+CFe4kSVxU
ED>ID;dvpb_-Ykw$#^p)mzbe!7J&Hj+0VnP=jX35#O14s>snfX<2x|Fo0h1Cc2fPrucDty9I}UNI
TN&5#E3AxB_jB6$iA;b+JeKOzOjHe)_`HlJ(fi9I`<#{8`y)F3I
