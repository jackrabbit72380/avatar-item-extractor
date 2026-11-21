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
c-rl~3wPT_vLO6dFv{l%7?Ctd$+E&&-YeU3qC0*aOUWcdaT$n&B-kXtAwWrVCi~mBUi}0>(urrz?
)lbHBogRnb#--Bbv=IDiEg7JT8w6Ke$$?>cKSPC{pH~@Up%}_(uZ++8_ZY5O_uImq!&B*--~#hP2
zxS1vB_O&4X-N1ld(^Ob?IqJTBfv<B#nk8wW{RWWn2K|J{ZL(({`n58$V`iGx{^=Sg}UOq29uaFs
3S;oghjHi_^0^koih1bLAy;yj3>@l6n6%kVphF4A9u^Y7n3JUf5?EEs2L5hZE72<~pOJPuytpn}V
32Gzr466`gw&nOt*Kq(yOtAG658fUXPG@Qqii<FAy!A&-u;E1B&GAUZvdprpUF2S3uxWQL9@gj!)
meWaa83)%(Y9P2+_B!4DASqxT(`j}`6TC=aQnRQClG%J3&*HRzl9ww1QgFOnL_s)SL`9rGWN5ayL
f(Xy@_2d$1DR(FgzQCnAE!z5bsl_-7im0wcpuHAQr>6=cS&(W5QB*Y6I!4J06v(0x`!nt$OrIGRx
)r`JZRBWgC`ZM_Y__-&|gQ>_*pi=(%I#QU<O~?@By2Co~2jGVg|E|t^vS#K|{%JlKC8-VcUIcU@$
v;O$%o))EuUQFQXI|MEABz;^`z0y4}6U!EL-Kk}=@I!=TqY*bj<D5~bHuco4pfXR1cGx7WiG`;Yb
;H1l^^o)k%z=CE$Fm{1i!^X&A^iy()=#myki7^wi)pm$v6tK@pQi2G*NvpCA(Nq&)b+mF8uqG<-D
?t^eS2k>{>kGk?`)eJgq7%PAKMAHc_qmS4qpvQG`3&YLQ7_cWT0QF~=7b&0spcOzRN)h#-yLNC6A
Y!<Tqs1bDO7nQpLI}k7@FIp*6BsH&1ADlOlj|EqoIJZo5xg2!5#Z}Q%Ng}(T|UOsxX98Vq$S`^9y
J0$)X5^c3yNeGw*$n2+2xdW!$qp$BD)^P8w0Y&K^n)fJi5(Y_?V<A6a}QbNnp#u#zXL0d*C9)+TY
QZk7R5_MuH-nL;%3}p0NIEk<FaVBA|>BQUxvT-xo<y#A$FFO_ye_vf5Z&p@;@nmQGi=n_-_#xxzF
m5K<SZ?02m8<4^qVCW1|PHO*j8BK+Yw6ko*)7(7%16psih41_dJ5H4*+C~<%=ZJbK9xF+=04?g6X
d7I_>V_qzl<HCGh<yI@OoAKM(>GyAr&wqS>GCDi`$4PJ$bnd(Ros0C@tGCbpHu~Y@_{GV4^{U$gA
OWVo{ktiA*y(hz9WMXo`1Q#dJpYYJM5iBI?3|_m&}4G4)8vO;e0U7Qh!C>+aStD#$M*$n4E=BqAJ
V?okM{A=*-bQ$-vU}L5}*P4-6MJ@=%b$=P=`o&UdKf=0TlQ#g{nF99-Co3#!}Cha6rtSXVYwP9>K
=YZx2gt{N%LoJHp^19Z!M2;XX&&8&ATM`*A$SX*T*oG~qoL{R(K`pZkaB3a)V+%}n3VlH!aWNr#L
*ug;#efT{v9#X9gBNqPoAfPGvLo#azgcBGsfKx41qAOup=Hb{t#!t-D>O46hljY2$IngN1DO%ng%
(>6W?Y`{O>o9yZe&jG+7??s+`ibpWW9Nqz83aQ=To8Zvydwdg*KT5~xaz^Ft&XX&rmt9>bc<S|HR
l<LZD8Un7uiwQE!V3YlSf)tS9!!F87k<I9|6tO%*a;p4q1BZcPSfkC(Xc0gE3kh2)`$=GH;xk9gL
8YL2tS->Sovb7;enSSr~5Q-;WS!K{RO#6uDnNj-K<HQx6_!)tLDuMpx!_>>Ge~f3hs2EDB#ivF%c
?D4-as~?NSBO>LcLu((o{7*_E2qaKkM=i}H_9JnRNfo>1KeRO-5Ah|sIKAfgSV^QTXPy&?X#dhwQ
k!SyfbfqMEYH`c)32yAX~hUD%Mjl_LLKxtLIQP}Ihb5Oeq+KU*7Xewj$(QdRnq~Z$we7u7NI^2kF
%frA&xx+HX$v9}dgz;&kJeuwSjl>>Csb2S>qT*g}bH%-0xnfdL@m67hspYkK3+Thh1aA>gx3K2&p
xX#QYymc@+}FW=EwJ4_(}uSU$T^rk!W7ZB(ePI07BPnkq~#HpMsu|WWW*}8m&CWg0zbKeV@*9(&r
a!?4W>q8&>7nOM3dVn9miGkwdqfz9-E!krpa|WDzZ@ud;#sk()iueBy`FC;|2ime?6`oL#Oe@&fz
=;#&8OhevzAl_@{UbvgVn7<(|jPCbs^$jM4($POvyIJC{+8OeaXWO%M+6qw6e<rmzh0yh$v3bPpU
b9!aqAikp1%vCQm231HOkXaNl85)WD~)z(PjFAolDbiZxE)wTscZBq~?0}?Wf*6&}@v4i?5tIx0U
Y1=BmlNJ#Vsszz*f?m5*S$<VhK7<M&XYRE-$n1m%@a>y#K=^x9-R-BkX7=ogmHb8-BfcW}P$ZXtz
`z2_GR<NC#go34gZKc3o%K)X4ABz)d?bZ|-P}J>B<{4^z5hvQ+UmB0Giay<n>c34@1JlY#vsE4F|
bxE(uxG37LUi#EVkQ2A)5qcJZ^|EM)_(si$NYkjS!3@B93gg)oDNOb{pRX**s2Lq6V2JmtW_0bCY
bGKYaQ2{p;iNv-WHPK;J`I9r$44f$@-APFX-i222m@5+E~CIt8maR7BvUpfc=U;G`AY0POQcHd&6
j<r&DL(YTnR3Pn}-kUI2nzM*+pdn3?kV<FgTeJiV~R#v4}KCN%%Q&lUUO0B?R87voiu<LGtZ-SLu
{*zPwlUx21l>g)$jw_(*UGF61W_FR|vv-o+j@#$G)91b0=RH)tclr#e(?;+Y=;0H6tQf#O4gmI^+
wpzrv<<0nlVQbwJ~eC!@+V{_YtD{mct$YmI-f34(R7vE$CDQAHG_N9_qGQ_GZ2}D>K?s}U{OnlhQ
m^m_~5eCBJfb}N77UU+4r!_lS8N&Pi1X6g^FBsD<O$tW)5pUM1$xO<U6QOtm~E}lYm>bU8u>1H#&
cd+-gpR;IYfiA+Mt0T%M=^)?*8G1=^D!FkcrpVWXZ`Gz+<FFP+UYei4>P>BCXO1OFjFkxuf%&{h^
OhCWxy^lq<(d|vB@bQCaQ)b+APy&r@|&Ca_9I6eM=a&|+jrjKz#Q8Eq2(+oL5RtV-rHqVKqv+5o}
IgKOKp~4=D?}7qwhLn_~6d}bRw@0!L>U2}m1?0rB@d&@8VgdD*pzf0O)Op6Y64G%pohpTO+nzRm9
^Wj}kI07&hWr3KFmkuAD`8<;Gr46=-4jc7Vj%$nuL5k0#)kVJp{kVF{ZnH2v6-fH*C=TMfZ&w|;2
<yd3j5ROa#~W=Lr)ZXvO-|ty{q2O1{t){KQ98{FdQM2Gz_qS)|TQv+7YZ&ItjxXxHN34#BiEL_aT
1Nr2+i9cok@{X<5W2t{@^-v{*!|(5m9EFRHTZ)(X(J1fi`~f@+~o?bChR+liv}=xdC^w?oruGq9A
t4d)ac$O!vocnqO4>U2F^g!0gi!(;KwNo9B;p=b{v_~nSHNO-xtx{4Pr`8gprlnV5L7!;`cMQRi#
KxpE$Sge@eQD12FaEGUIwYZvQ(ZtAOgfq}5E;)6_j}jiqpuZ2$fmathznp*n{$j^f!QfWGVvXQQ;
Hu|09&z~%s`j~28+~~w)VJ5-P>;;+wznSu66&%3g~mz%wZ~fSpYFZ__ZrnYS8t+xL^3_z-KYU^`-
1z^q$sBG2*rdbRV5zTC6b9nwJry}o<%d=H+%A?)MM{ph!b{4Lx*%%L&K_c<Y+7_RK!GlOa;Ij;4U
(cpP=_4YYEHx7k&ZT$25ayII1r~_mPGr9Y1Qu+`59zt_2P2vrlih(q5+q7(FHPW((Bv9l>7V<+<1
)d~ueFYM{FOTH!x7YL9U{Fme?pxMe^x6;;QicM#gW$q`8SZ11kg2yZ2i(2k&u=iG=1521xm1_hc(
2@wF+enP6LAYb2-X`<Aoy($&$8zNKgz*8(&b!WF;)pZZ$6Tf@YZskd40oS}PvLc$w1rIm=jWu>tP
UxfBe?Fk8nPG_rN-dJPsL1Ba8bTpfGvv$;xMavWy7ckSIMFndu!($AjlEF`72ZL*X2Uttpp!3lm=
PnXPBXknMy)8_C5QIq5uZP&CnqPt<41T0ltznH_aJCJ<%{R0HjU{Xv`~-u<4@SyZR{OgFe_NB7K+
la7<3QySGnvJLaFpyc)gx7Z4LRp>S@sJG^lv@C6}3@k~7ayVA4(Py?m+3glWU05u%&M(R^cCA?+G
!xmvyb>NcR~+GZGN7duIM1t@`4&G4WqPfry}qg3OK+YG50c1_)fFzenvD;;Ebp&k>^?MK4cXk~oC
SKTAtSRw!MWldg`w`m+maYoI4u(wBIk|LMkeVk@F2r<R@22mbOEbwl4H3c>W<(zqP4-?Y@64mYWg
K2gb9PpwbQqX;^*cpWY#a{5@=ksopYy$A(qee5hNv>~zf~Y!z1$+n~mZD^O6dbmawADR;`P@ZwYM
W&$AnB~~6a2da+S4Ed6|`1ab`QjG;J$m@>okMqUXP`8{&+)%Df~H_!e)=y3W~0<@ga8tb67;Pm>v
mBjo$-d;jrM<G`h|SV-XDTY+kH_e3}&vucJdcfhuISs~Ms^gMZK&3QjxFuwTQjkg3UZxQ8{e7m8j
ADfR^gM|2A?lG)K8m^jU)8I0Bma&CKFb-~3Ghi#c<(~x2ESK=|$DHjmuXC3Lt;c+cOD>WLn8)AJ*
I+5A+-4j#fA37to*5nZOi*BXiZnfVob{H9f>qLMzVFjoU{4Q|3*x|nLky<sVMxdc;3?%pDxY*HMV
i^mj7dtdLd`cha2`wi*qEGmYOd8+`{{7wT?9t--^3lPg@K$YLWShcUB8pv?C|>I~j~Wj4Ag6xo6j
eN8xS;FCM)0oyK0?hNplf)I4}0|R8XxZC!%I{0l1p0jhcywS$$b&BaPQzGoP_tqBi^}3=L^HGip3
^SgdlwO9Hs+D2@(bT23-{y>PJFo=MFJ8SOVj67?8BvM6*l~eAzgz0IqG~oHt^UlrCrU73x{ixr1*
w$TB@o=WX1Zc^INt-c`eg*~@p<#We{aP?*M}5R8~Wc!*nsB{TuWq*%@4Bd<8hZ2%32eZ>agH(+s&
#z<icdh9g@{btbbx4J{?xirGe$q`UKY!6|~XN}l7TmsZCQRx}-HrmDId-yQeht(8fp&!}IumJ<q{
sxO*-tpgxd82I^ZbK|V#c5EE2ncgR2@p$`<_oRC;eu2*h5y3=@lARF)ObrbVs$=j7|q7z3Y8d(D7
}th#5QwIZ||+QcO@PB)fMp>c!dCS*oEQ^cM@9TGyTZxGa&5*X(p)Hu%vaum8j4+MR5E?UFN?-Xbz
}2Oi6v|4jbhvVz%Tl?D88b_4<d{h7qGG+K8s}8>Ey2?tfS=fx>AgcnU8oMs1n^?sO1_k6}R)gi(a
tN`fD{ghP)B+=+oUpzq^GMR$m!TXgiOuA@g49X)Ccq0j(k*n9M-qR(-LQU!wSu-`rK3e*fp0qza3
T(wKnS=UzwmdAZR?#TK>AzXhXr|K(U0Mgh)Zw<#?t4hzUvR7RtncUZ54c6M<fHiXf;~aZchtIeJ#
r2o2Up$(|1zB1R2H(tO37P?X?(*mA9fHJujA%EmLOW?x$y9?7Ma+3;@DbN}-i5z}3wwkM9}O<-F(
P2MjV)SLEmG@$q}3YSsqM&g())8m2RO@*UmBa8TQqUMQ87R&bibhx5qMbFIg-bH9Q}QDA&@0vM0y
$IAVdrVCV^HhZ6G_cH>|EonlapHVu_8rt!5~8PXqb@Td2v8VE3p`J@`aT4z&Cj?&)zn9@Y#5mCu)
YqQGHX-s@ST>X{n%#qmL3u{eD?WQSEek!-*}#u+^%h6q@p_uoG|R+7mAq^#(w067glv3~`g-Nf!_
kqm7x+Ls`BEtV--mg995@C)zA%c7|+l$01akAOuOM=7qsGLPAK7g;TCOw614Zu2{N3*FA*0!=1Z+
RKUK<s~Au0Dh_vb$p4%W3OE9YYWDW;mcgkH>%lhw2)I~w&qc?$er60x=Hd10R8UwhN6ucbn%N{qH
CAvxFsA3g^K^X__i&WFuo}(abcD{HS#kwREz7PT8--ardn|S=Xf&aA=Qo3pJU39vqNfvf2)|JYE}
$OBNO)jc(84GFof9lJXk%KwVpdOebw+_%zq&-#jIB?=fzx?D!4b?n%`2K*1v_(n&Wze0Ow|dnowW
90IO9j=hHacp5JQd&Kujdy*1ZW+xB*Bm)G4|-s^Lw5gO*J@kf|1Qji%|qmmk|f~QAit=AeG1Wgn(
B#PKNYqtJ4>xW2fF+sKb+dU4II$OiI;k8MUF5~~JxXkd6bD51A>Pq(-xJJ7H9c%mb+-OwvBRuQzZ
ePx3>btSl&;fZ*brrzm2oJ;x3n}{&Kpdna%ce>j!Sv98!Mz@6vZcaycL0A}{hz`xSo=>(|5`o&5;
!TP;CK0Jbzkpk_F1csE|XQ7Z_(mIx3(HzU6K>GL!QL!JsXiipPH;-bv^cLZ?DX~niGt#0GOAoxd2
cv|CsupMUXG0{O8uR>OZ*(w89@x9NcHjB+3^VqI@%&et3X0CqLYj@q|&Nu?|>_d<rB0*u6cZ9jaB
=4228h3g`ms+BVk(Tiy=%mkK2fzkgj&x=+9>1R5khvxZ!%3ETl+6!`KbS13uCgjDQ>D}ts%CXhfH
)>Q*YZ*W|yYs66gHiKm|xNQdGDZF;=cp1;%fIJYRQ#}cL!FvK7>>(f$*RazXV!Gc&s{jIVaHp)Ca
AP4wrfsIl2=|22Fn^@*4LKU>V>7mS{@nr&<Rrc3a12PAzJ|tD@g+&c@IkhJiXPlcKt$}2JrRH;aO
<sTGEoMgbmb&%Vw1^&y#CNLf1bn^dE(YG3>|?zk8k4mV_v=c>3%{{*@gNz(APpkwI9qIz6u(yLr`
h>Cd#9tSeUiC*cmA-YFOR1uVcJ?w%!5My))4CuZxjnYp!-mBWzlgWTQCG)K(cb>yO%sqgQIHO*Pc
$yL~H!=N7DGI}RD?JpxiSbD{RIn~>q)bB?ZG23p2PQ&hyDzUzE}{-k$!LC=be4y*X_DSlmI0EP|)
WuTk=yN1m{uB84=ZT(xX{*A8hvBdR5SyH#b1MGX7u5YOuD1W1GQ+aE{hS9(oteU~S0Zasx_HYXd8
!j*w#-m4V=<C{iyi^~38wavlso-VKRUn1SsDRy=_f3R}Q28P0&<kw9fJ}pgU2siRU{2cS-PQ|@=S
yu4*w!AS^74A!OZy2r_$Ye7_k@8lZSo7MfEt_1!91#p5ir=!v~paEO{_1men7Uj_Szw>D_A&7$2!
OL6$E<Qm&`GY4YX|_gEmMOaGs(r&X7y<^l-g_AvW<)^}>~elP1y1vNIICv}_Gg3>#T`Ff$y-Pv(Z
K<dR9{@~~_Q3`A)O#mUh2_EUgfv)rQTg&A!qw7lJ}mD(*)k20>IUkw75*S@~Ny0R6%zzy3C&-i>~
d9g%mA7Gj=+|3Hk|3%DB>dexj`aLH{8bx)`_at?E4rzh4+MQhgl-^uO5sZ~^A+RIv;QM%z6xqV{I
m~Ck!ayMkf0VOE-XZ`nP)4{YU2$kA@+yH20Yua3D)_KWKeinUNe@3jz<Bg%kG6$_64rB#1@LUMDP
_c_WaJE5+9g`Cb3c#A1*x;cy&ej`Xd0(GA~z(Gj9$t=X9_mf{pCnEw%L)3v5M+Fm;{q7W;MZ##{7
UI?u2@56sTi8Gx8t^t-&-ksG53E4F}m?gLsN=WUxGAkZj=qL#r_~9bx-1+T}6c_@Dy;;ET3?BRg*
pgrTVIfb|u}6w^mdLVmJ+!Zr1faIQ&@e*7t*Xd`3@#~d*k-?bgDUhHF!8zzIs{dVxq8W_lZg3;uL
HqNHm((s_BrI}3DCWjRy(V}d=ifWFKsU<AT-A&fM2W*i>j)E$!DB^>u-#rK`6gse|61!w=F*0IYH
x{8s66xSzzp4!dGNpqA+4N(Ao=F%-sL)Z4;7dXe=ZGiPn?BBHD-QZ%hv$WL_!BmSlfWnV_xJ6zv1
Ur$-XRg>E5rv5SoOJ6yrt*|>t~4U<!4WkDp?c6@BReq4ht(#O*W3E8_q=3MOejvK-q+KTO!4kXGu
=P$swMWQ@tN7BD7syQ;IK!rChJzFmDEXJ?*qh7t&V99i?HatYsDC_-~ub34N$9=&}<&wOHQzPd;F
r3;&_Sp7Wk^-x~;!y*wofgrbkYTikU$q+uvmzeA~#2Uh)_{Jap1)vvz_ULxd-S1IW<*jI{Y)(&2C
NWck4<wAYOqr*KF5Yve`z%B0W_nQ0rJ<Y<fQiZkVq}fHXKfQ}qIf`Z+z7FjNZWgg3^?s9LJk6Dub
5dpkd~9iU=nCT~Vh^Yvx?aR9;Mt>TRBCY%&!-8iaw%}<`|qCxA#4xSXZ7~*I<4~vxc0+FJ2>UAWI
2aU#K3%|DQDyHbctpS4^^l<pg=QVGH^&A;wa6(4kpp!BdWJFXP0CAF6PUUG>uC`%*p$mLriAyE1O
E_Kh+ZI*<m$Wz^<uKl#v8ID*VRK@*Y@EbTUTh{7gpqvt+!;P%EQ?80HAyR6>A8mzlJi0-W34l_sO
TqOgK1f@40>i%YwvVvi`srs@(2I0h{n0aKHt6cWRWT*xN86mft9)%2BjbX9}Mt03wvVkj9e=D?x@
?*kPI(b>%?UPkxeA#$mYg8ZM$IR0eo?%ek7ZeV>#b;t;{3_9&@x83fvd;199nD$k06^+eh$pVADY
QJlTA=t<Z+-@v^VAmIou4B#;uS=XKw+(;QfGVom*pl~_=%{)>uc0cq2kq#cbZYAmo)jGv=>bB)g8
>s@J$kkj?<j`7DW>Cx{)6s;|D?CCp7`^VahN{BJExO|(IUyK!}6>3Jc86Sqbj#)jZdqp8k>bnix)
uFdo#aa7el8tS48_J*xSf8uw1!@Y2YrbAQqM9areNjLdXHc!LO}oiBBf1iP%O8n*k+?6T=gF*CAR
#g1nplQo1!!<Qq%TCMcDFjl&#o`IY8Oi2+t$O2ruau?&AI6%gE|>m=Duei0$iSVTUSiU{<vh<vn)
{H}rbRd7ref(3<Qf^!FBA~ih~7dn3>EJuba;H0@NCDB#2=HCFTE44)3f)H!*b*{<eES_Zx6`DvMu
2FzF1G7&PbWhuk9e2yPx*&0}<k31KTwl+HhFeyA<+K-)I3Sgfe{avHVhS7zt=Bs6H5~m2#(xcT7}
$PoTneS)jP1w{@?_8%4z%PX7d`r$V_d-HznIr4Me>fufU~*L>!ZSBB&ZzHRWll+x(a@ZluH~9x}K
t~0M`?}S(56A?98{a_xmKy$BSgn0hcLKyQAu-)BPyO@-}wZo+JzGAXML@%N+k&L$WL!#~5;Y5)~9
dLs!9#A7Zm8QA)Tl*3h*nrt(gs_Uv(**fgZk=qiC@VAN>TcI1WOR4v5!NnYfk9=^}FQLJ{1c4mrT
7bJPdDF-Gy0%}=YwGQzj5xA|ZD!ZRaHU`k*Sla0A9A4dcTYyK4H;ma>?kD*XnHFT@h94i5ujI*Hb
%2hv=xR3v8px)I;$w}g5vRa1W8nIb8^lX)b2y%@@*<v{+$ZFYn+0Xy1xQo^p=!AJ-=PULJQ$BCOg
09kr`X4$-)B6=S&j%*2qm{eWKDF**}KU>#j)G}K70Gd?eT7r6y8<U|HI$^d+?X()KT!;?`3gHV=g
yPF&e5p@NgfgcBr1o{RUpZt4DNT?F_3o61DiB*ca4*GEq^O*i^b_oQhgPG-|+oA%;Ly!j3kDp|_B
KNC{}EE~6^KLfyf+Nfsxm`Z63i2EY|_<pdHB7OG!0yLN!4EtCfYwIL634$hs5TQC04$W8;(f|$Ld
$toCEE;SZO20<-o0D@jtVdK?JJCEa!VJTRatRlQ;hMQwWX#2lxw45)H!wl!mU^yRQm{*q$y`$tMm
|%i=qF-9ex#K!=$$2I68xh%~WpR_CKIvyD*@W`Zc#-8G8vLU*0bb;$Zzrh0bQjcu*vm+I3Q<njIV
#-r6hRm*W^_H&q$>-`zrgqPn72Zi^HK7OcJPc7SBTW#N^(qpAV!CjAp;dP$Sa`rP=$F8biQg*luF
|sEWpBRfs37cH#(8nETE|aRBKe%`BYg4D?o3q>1HScuvU(!{3yHp5Hey21Ev@8hz8ZvQpgditKF6
TdvqJaIRf1M+h_l6BCY0{_qVk%O_QdiX=&gUBA|`vufN_Fzy6Bqr#s1KfrgW;8*Qo$ld~ZoGprfj
4*_NwVL(8|yOl%ci8`B}aY7Md4)Fpho3|*4c?KwqX=0L(aqwdA1)%}V3ChT&dR7$KjLK54w^;jX$
^rAVf>KW!^=M0u9YK2|xQkZ70xx1Ka0C6zZE1zVdN6pb<)u=Ji3dTkm`;;RMJiNz<@Up&D!Z1K3|
%iKX$7M$I>94;HE`tIVQv4JST#JD&;Ynjqqg`mk72|c>fk^%qUym8Y>|5ComggHS%gTpVF;2Jx85
DxZSbIdaAkfm^;L~H0Y2#%reVoJOtL%~z}ebM4oh6I3F@vaK~gD}bX(50kvZeG-6F?hB$}S1eR4F
FtJEC5=(uIlr@;e-4|G`B>ci#jNU;YU7w}rhai(YKBV>~0(1%=8D)2R0g9((rFcU?pRW4Dbs%}KB
Q96~>RT>SY!c)idQ*aob3U&w0P0{q4m>AV3g;&!9ctQrUR6+vf3mep-a@;yU@1WAI(=PdG_{diHh
_)mXyPy@^+Ev-pN9_QuiSe$GEWfBulg0}5FivH!8SMEC>sLf%ZwsHQ8e(cwF-<~M7Nz*!Z;p$!kU
HK3-4^2Yq{-hz2_mVMnEc>-PmLRqao?C`O5tQ-_=9BFbiQJ|*YcxY*#oJDrS(<-)1N$iFtLC0Lcm
~nJUAry+0qrLqIv$&tzLSK@k}_(TLq14l-W1t-0rp&Er400;~j=`fmxWCd!&J)_mMm;F#|xNeP&=
5%|}Q?Do+1nLuL@6#OeqN3#U{`=jaMi&;iiLod3W6s=8thz(z%s;P@I0cxgE5v%6GzjKIlixP>D7
j!eEq5lBKSx#8fwJ1GvMIj{@UX%0hx+RCU}#aXjdip(r*KCCw!t{!fr@m=W{tU7k<57NIyNMq<<`
Gccv_bVb_d#K8LAJ$gP|6q?3Bx@T>CDZA02CT}CW2CgTt&cJ{YM0E*OCFp5r=4<UoK79xTw~(_N1
P&Wn*Q2D2TK70Xl{|~*vj5%a%FJ8)^n}8S*1;W(CJOulL>bs59=3RPw+oU=Vq|aLzB>KkrU^uveL
DW7uQP+BKnTrgqBkG$mIJ>b;?gn{h;+|EZmbgucyX6w4=#n6iL%CR8BLAb6mv#TqX-KfI&x^=^Q$
$NI$u;Md}@!1V)mF%YfEd;Hv&ff00%c0@T~rZId=4T*UJ@B2COJUR=kD^K5J!4`#&N(KDh&VhW5f
L&ChVh2@-5#*mIHzKWL9LP@0Kn+#9NqfowI?5z0Dr*&FGJzchB;QN7l&cX_^T6hWACJKoA&GX}c%
nraw>pv=BC9RoH6UhQ<A2O=4^Z^a$<ZMb^(I4zAH`kMj8}>E7Sc*~{sTf(v?lVHePNQW-a(1z!R#
Y>PAS%&J9!!*a5ojW#C2U?|B(VpR`VCIaQMG9~Y0^*;hMn6tK+_D3i)^i&9<QsFv+T;$uuu&qPL#
GXj5sD}*D*$rq_szGsBA3dkV@)Y!ts|iqbihYDOR=)qe`bnRdsvdD(1$6)*jH?R_`F^7LQ;y)aH?
z))Ainb;$Z4(6L>u?38pusOJ|uZ;``6l&>1J9fh{x+;fXz7A)c=voB_1bd`s)4IEi}Zd6+`Ql^@f
h5)`!*G^~)&CAInt6jFXD;7y!mPtoV`LR}@atsa^X1nj0Xz>~r6^qBC*vODOhc^z`t6_vRjxtacN
<wcUbr90miX9M$KOD&tGXu>qZ_w6I!)xLftywE$6krmLk--M2!X^nceuEZjcL3G4z+*Io>SfcOL6
hs0RV-=>cZ;kbTBxeaL7ZSF7es~8h&iay2+!rwNb58Cn7&ANnmfQoEP%w0koC{ENy~l06_iWG&zI
SKuy@c=hc>mtis%Sk7our)y^K{v&=$TXd4naB=ah385s%zLrR^4<(5Fzgb=&Ju=%XTo&3QwaStJE
@ahIudr2zdUu1=a1oFiA+)8T2Oq?gN>`Y13nIP)E-ROZyDi)GplRFYq$)Kh@aMS6Vp{PYw{&6f+*
U-vC(n}jCgPMWJQwtxUoAeqtpe#w@>BonXD=@gCs*b+@iTXY~=CXT3Ky2_?Fsg_nb=}s?F>J>A^#
$*oJYAv#?uu>qioBnhn<{|{TJmKS~MXR8!3sKsJF}}%y7a;FZjsi5`3tq(e$0D2a=WI+za^4Q!i7
6rvTEkMhAkKW5QaV_K8=CWg6fvfF@Z@B`V^WFFIr$2ovh5<j4MNi8GD=OORkkepa)e!^Pp+5A<Z1
g7{qz&GqkKqG1VTo&hcAPNft<+}k_E>B=6;{X=HW#Ol1PSO2R`PKxh1|wW7LH5C)0${8zNWWMfNO
@qXpV$X0w<V5Wz=|&=DqdMwHAb!%Hwp@^MD-4WJ!hKBw#teVp<LWP}KlUojcNuZDAJ2hWI}@9D(#
NL1LFndmM-N3JGQmh|}m$SKi0`Jd~(<S<1|3+<E-5{dcD*HTyjHmhKjz8qJy4cft(ov|jt!@&xF<
ueABpQVZI&g0zkJ?J(ZCD;#RHfLvV8bwIoBGBXr<K^FOD&?)Y3%N+eBd2MnI2TKEH@7*f>=Vi8W~
)Xx(HpJkk9l;h1UROVflo}!jK^1ig3uxbz@UBDRF$BI^=&=jJ=Dq;Ekxs|=oX1Mfcro;+uHhq%rE
*E@Ncr5&D|&H35U~q%SJXbF_1K1<G(n4uMaK8ql{0lAQai5ulkE84PEo{gL^pVsumiYGC!`)Uf73
Epr@w~X}Axc;D$#TM>UmBSHbCve<7Pjwo?o;dQ66pl=dF!=R%lt5v?#=iyqK4nZX`^V-h4}a|yop
hUuCrm}V^^G}?lI^ABYh4+x*DatuBV93c{P!U(~$VjNHub%s_zVoTK!QGRPpl7+NtcCCBT1=pDc`
tr%vP)X~x#K6$i2Qr%h&@FcwE42;oE`&p0gjEWe(3EZ746fr06DzLl2ALkya?N20*fM>NM>+}a-f
JY6AY|d~Kfb|dPGip68zT@FcVR}z|5852CCD!wqQ-ofF)lTMbn;F>_@i4U8s@75PnFqMPvA7AE5q
PDs|j+6s2J?E4|m(a8>D*4V$y<&#fpSC*zmOXb>=*YPOTIi`oT?<-%OKB{hcgf)R!#R9~Y)dezPo
+srgC~Tg=y$sq~3jzDQ5syg2!pa<BNuDGu)R{N(lM<mdB~H)p4B-<+X^$;A$ylVb278jS{810I``
f}(gN#A%_g1z;bg>|p|q>z6XiC*b%lxVwLcAsA`bVOt7LcsKF=kEbtq34xiQ+#4KvvOqpp--wWaD
*-Dn0gV?+*fV&O`~2;j^W)PuC+|nEkH0^CPO$`4uAwFdpN9g0e0+8K(}{e1cl!Q}CU*9>(|04-NI
3c5P;8pSBgHBb5Jsc<YK$%b$Qu(>u9Jd4-GcC-ywo&lD{Ff$cK*NjC(nO*{_3Rt?DP#6XIU-yDVw
6N@oCE8FEHKR&hHoL>*JqCFHYW_{{Vy9b4<=~?}v&N837TfxD+@Qgd+x-YP2!Jsp4_P8<!~%vWga
?#+2cYn4K9LFNvR^?6JISb$jf#xsNWcgfhEexlN2%SZT(l)&!j=;E|;xAr1@^py^he7@?FgvTRIO
+%(o%ra5C!x>FbOo^=}?0xPKoq#sxeyf^fEsy2nTg56tvR78bii<8<iVpq(Fa<W+9p3U)Tm0zbC>
pYuN*6ZrbdajX`0{~V&pn_ydq6KbXo(1LxevohSu2wQMgBM1rBa@VRPR*Y4#z1aIOz%r4AyD^aY6
&VB?u*Z+D6j{IMs{c!z}S*6QFzRQ=foPFXBmcLB0M9hK%LTUt^EE17S&pCFmZ?Jd><i~k%yjX5MR
DYNMM{#vn<`2z`-Ih3df?hABrXxHK2Y1-h3czkMAa-^6>a7_!!4*aKolN=<*#BW&dB;9CQtgA04-
o1#nf9rFi${a%qE%4mu~O<{~_fG5<|8Mb2hL91)(*awb3x+zHx$pL8C^KB+)g#o{heJZ~Pysi!uj
nWET)v$E~D@OhaU;NwO~Bd1CwIjlC9>HB_oel$c>_N1$j`+<(=ER_MZfq7XJIRY-^7rWR;9?#j;f
S-{$MVxN#3QK9n12X}Yjwp^(b2XFXBYnt+Wou@N(se})8cW)A*01;!xw}D@ja4OA#$T0;2`%~63z
(&Vmjf=~brttI=nif3PLE9~8{FZ*<igpZndNIOZFqSDI5+k0)}%Rp$F`RHGy;#yP`Rs!ioQJ~3R)
f&g->&U%Zz8pe1DVG50*VFGiykD@Wr}mDgqBU<gA%<9I0+d<J)lV3Akr7HWWBzbU9&3UX|cd<P{*
IqB>$~KoTZuS#p+;+QBm<v|^P<DQ!`Hah9G*@pilMPwX>F&P@iZb=$cO_zGu0C_Ai8YJBz0RfUh2
3nWKPpu&q>R*!6V^7dUc{a869EIR0;?RHM*T{xkpNLhpLHk^Da5V}nhfCD8Q2KY^s6|?4Iz4KX3U
537PvS>u4!BvhdOf5Y<3N&w8Wk#=OJ1AQQ8T{9PbT)u{nSer<@>}NOjcxi{rpZ5-v4>cS^P^T>#G
+RMM6T-_sL@01L~FP-*@FE3OC9id#<Q<E+3Q=e(D<^Ecc8mBlL`5j;7NL&p?@Eme@*Bw?R@5BeDO
~k{g4-M5nZ+b2ciY}zKu~TNhKx#X(UldWAh#9W`!YKQTA_2fFo`Et)G#Re(;>y5=A_U<zgm@Eq<M
s&I_ZaRyjJAas!1o%)Wk$(cL~G;kAYXv;9tnEinpI1HUpKh!?LI(B@aA<=jIv^)x5j_1&wOOxSTt
bszTV4SPQ01-#|?Y*R2#VsI!f5por&Pn<4|Gf2g$RBdbl&+ueHGjI%r5TUBP`tU+5N0SRg<I0l_^
%FP-ETpJ_GR@$_m%bJylNX&#6Y66`)%|`|{Pn76&xklpTp$l2`I^1RDbO;1>grED{mBpRTrCZm^;
daws6WSnSsw<lnj=bHFIkynP+ecDk%OHaqy4je{hVd72RL_f*ztBH_wQV}3muV~=19g1jghGyVw0
m};&EgZI}+CTmJg;i`^-6vIq(&#+S~Lo1bqCT;h@v{HfmiRw_Xl^JN&)TLVQ$%aE4A1E7_E5kuB$
8w?PXaM)c4!8RxPgn3^5z)oDB~LOu~Hm<<VImT5gMQ8A;(?sIbOI;tlEwKGk#6D@s&;VSSj^2Vdk
m?QF)cvbZPk4;jFNbLroc8Pf#s1<D1E^SkXCqh_DV?*nLc%AZri!0jWC*jb2hvf}P9Imh@)>$L{w
~40<OF9gJrpbe=dMJ0WAp%3?G!)p;f{Znij=f2F*Z8I|G9hRj#YSWq)#{X4%X%JK4TpK?t@zERrN
yj38sF;A10%QKV+cNV(W4%uYsSBU<gl&XWvuwLs?B+fd$2`kO*EDum{)M7qTWPM77n=SG`I#T6fE
;Pfv<MI$>1(_y2KtfT^l4-{W>nt#zxiulRHHB34JN!1d9(-=2+#;p%jxUvd3~3b{#A%qhDqIhiwt
iT|hlvW~6DHG?XvLj%pT=8~i)3GhL;_Eafg;1)HRhRH<#{!NH1bL+>Tp*IlG<-ky(+e>y%teovPZ
e9E#;&RjES&5k?@*ybZZqYq##(}Hi|r!m?jqZde&l5(WY7cX>cks9k0xpe?Jhtbs?=|ovLkj(_&z
Mq}HJR{hm^#$EroF~PUtaAlHRM-Y>T*2I>TzIg(1{~8=s~@!6Ff=;J00h{$b7`^ZrUJ{qI6Zs!>i
8G3MMGn)`~7a0lx5u>hnwT@9++!eG1Nbvzif36o}Dl|PeYN$&QH%@otUP&2j6yC^Hx<|>ilqW{Ne
-`&2M3sY8hezJZ$&iGNxRf9tC;x<Es|N-XedjiS9w-f<^2B;2qr)W10rAp2qZOH|UCc5TzX@HDYu
(fLDEf-5X*c9ZW%dao_3iFWX_0N*x6~XIo(tSbx}N^RJK@a!f@bK^F}--ey+XQl$u%jS2*Gl@d)Y
f_6PdoXl^sJ3=bP91}htiG$f(s=Nc7Kd1AeXjn&%&dXZp#&)VMCssYSIOy*WwQ@ou`r33D*}{Zv3
BnS#H+_ur&T+&7?74wT3TcRO(wi_X49r*|C=Hh@^qqRcvM5A#`?VJ?1#hm>{Im)XnHok6!=xInx`
ZcUP(n2%VS&==kMV#JO2XBSMaI|a@-Z3Ci5m|#ftF5kv(6Nc$tx+;;rT~S<EKKWDb!S*@x5VRL<#
HC(40V$DaJBTTh4=)>{{y%m`@BT66wH2(xY?fi&%S0#w09aRHt32%<!Rn_Zcik^EhQ++s%PA>=+t
YX(ZxniSHM+jM7;fgeI+7Q{7`AUgKS#6bEJ;^JI9#ke7}1L6M9sQ|5EIw~9DI<?UO|#X3%#(vx3F
2NdyCAl$jwL2q}V>8p2%F*G4R$d1or`>eN50*hSLWO=F)*4II$z8ZQ)@y=lUj24b#917h1fPAiAz
I?v-?c*Mt`h2IzZV08QkA$93lj>Yujayi$1+{1+pvfDVs7l(;NtBnv5t1=Mg|NY^0ODv{jx2PX;4
=&lF9%;s%3jjmW5X&}kI<>LZEc;l!`f1n4K}u35Jk}4lh>fgAEM%vqDR(QEawTBCF<VvXnY=B#Uq
|vNG<u?&)-3UfWy9p1r;?S!ZHI^Qe8VUy>?D{497w`ntXW~F1{W-dD_3&d5Cw<|N0-_5Np$d-`%U
>*GhxHfPw8}d3t%xAZL{CGSG?n#P^D;fk(!VN&yGn5Bi6QQC=Y(js$z1i~v_ditHg4mF3fIu}r^K
MsRFSHn9!^_M<oFpH3vi-f{5SiCe+iM(gAmW5oOkv-<j!Lh*v1x9k%K`XH7}ke5$EvoTqdeI_3NE
FkK;ZnA&H!*RY;M;h?$@i<!Mamfi*85;A9;7}tenJl7fa)~MEAs^c<pK;KycdXg?CzWyki(_NLnJ
GP_5E3j)QQrv&OV@GXll)BwDQ2r{=u@vGs;gq$IJs(8wXkkj&bi_!8Sp%mhAaG4Dx`F;D-)puE$`
a1>^64gb3$<v&YLb&xK|~(dr5Ee_F|@bvpqmd&h1XW*p*CXJGNXyNNrxKZ1JN&P)EidDqO>kvN1`
Nsy#VR#vD~KTA}j*qC6^?kvA-Jq_|mfj@*M`oX9*D{wbT!cJPY0QpOO+F(bP|leH*S^A(%kD@`7n
yb~jB!Y?+XuKR(y@~+rtwftcDu5VCz*>kbO6WZ~VmT0(I@`YT}f>f}Qij&#%=n7_>hhh+4rlQK?7
L`x4XtC0EemYdAG3a&fuXOly`c&yf&$p-ax;hlhP=)3}i+60x%yvMrb|{tAe1P6bLvD>+XQ=N6CM
RqLQZBk*Th0r*!Cs>#p)0=~dI|k3%Pq3Kr7)`G=WD-GVJ{^WpMtbg#*QdU_hB+JyNu-l)+bfqI>)
q1c)RU!s1*rAdmmDB%iBi%N-b~gWumY+!-jF)?Rdl00YRmGqrKeLMSl~ox1G;^V@)&FP^z1fj^99
&8dQaKsBF<rS@#vI7b#d;GgyHH3nFhElZzBuC1dKej&}JV?Mabw+QJ~k5OUr2LEAwu+8j6_{v>@_
xfs!eT3lQ>Y%k~9q>W#S_hC78O1!h|E^TTHYO=&ODpX2vh<w$8QxF;Ad<JAg5maGk$W=nzaD+j6^
^c!}@l8b9PHp9*oyc1{ZaXQ0k<OBzn)oJ>8J?JdSz{8t1W7kZ!8Z4%f@ljciBmcj7bO}1G-~Iots
vzdAAs@tG0z=ZfLg9Ymh+M8X+#ArcOz=RJ!z?k4!FHV&c<>$lCt6p7hs?aRyjPcvGh`J5l8CYUBS
_Z(eZ&KaS?GXz#N8MnMV62zMmx5a7b(Ygw&?Va=oepr#?b32dyFesxubU$v??NkaX(51n1wsf9Rr
VGx)HaTvNtg!e~)3l`g9PP1b#=eE$VTB^q~j9%%d_BR@WblRUO|vJ02@<mw~bOJBAdIrxAmvCQ>(
-c(`;3^b>m4l4#woVa#$w0p^QK`zPqCIvBqM8!D(ayV3pZ>IS5H~UPaS^QphTu?ZvN>nX__VA<4Q
RC)Uxqr$==U>6TC~RWU$9WTvS>UDOrE+v##116{q=~0j?W$e9mbf}ngQ`=`mRhx4FwrQY1n(SkpH
*E;PiSOS0$7D;&R!1miM5($w>gAB7L=^sepBg@=qXv$s7SEtS$Ft5pLr?{05>q)hWLCX-ljc8(XH
T5a(vgO3xDzRxk(w$jlE~@R6!VAL*tVAo$Gf>&Zd^wz+R?qB1@jp5e2FZL!Ry4uxhfjx&k3&K6-M
OZiG>{&Fbhoe|`dZ<k{`P>W;P6UB~{BK=Vulk<p-YnSg4Jv3BY5!<hozg6!>y4zDV)_YX?jqw6$-
ZbJaX`PEBNChkn+c&@TmcCA+Tax4C!><+$CPaC?#qiNY^HG@;Um8Z{*+CFPWZel=D2dWgpiHp+Zq
MJNXaKC!5YsS_Jw6C}><L><VSi4ukS{;)kFXQU5zTUQuS#-Wg6dRXjtQ2EH+EUl|^o-s6EF}AU^5
@brr6k?Fk!<I5Jc_F}7Q3OV)_iYtxj;hyo&wlfx|NUc82Lz?s5r^fJdq1v<MhwqAeHm^7hxjHhv0
fpZ#p!#U_sY+K(S*AFU7L$235bX|9OVgKPfd|8l`wErj640E)e5>xGon6AbGmZ-{K}(<wZoNO=v5
5@Mo6;BWabYcdcT%YH&xkXNzu^w2}0h!Z^t|zo1!ps}&?O^tly7o<&kPF(NT6qu8{t0X2K1!j6hF
ba_L=(krC2O3;MmTtu*4Fu286!Miu#W4&y7eM7#-cv~GTQzNbc*MH1c*b#L|7G&?gf40jx=gv=Gz
HGaZFz4yDF!qb<%LqH3;1^Ca@AA}#txKS4(AqH$M6LmnX%S-t^F?+?-o!zX%v=>19}CF3P}X3b1{
;u{a(GgY!8gIa?W1yM)K2bDq(x=PXB!n`N4rNfj{&yujr7qE@!Kw(yZVtf_arOXn`QbjETU^R9<I
=VhjO?hRfJRh=_#J-q<6yd7=RCI!*64tZ~xm3s;cAqwa1I`UN1D2-8{S|Y!PzPV!w28aew$N!2jZ
6frjN5_uYsL%-w!>WmZt(^oJKDbNPcfeTM(=jkD&>;IJ7SG=mQR_)2xV;TOl}W+sYkbNn+r%$vct
>uR68c_E@8Zs*zviM7I}NSGWJQG_5Dw~Om&TipK9-b8yn!gSh8&%S>TzrFD34t|sSf{ozVS;M>=b
o%}MA>-Ddho7;u{?fDxDPM4jQ|_+V6IiVuet;kNMa#x3)YD6)e!S(x?4zCg-r=7Gu?%ZhGBYvimq
4CeU2O~VXNo{glcJc$E!fYPa}tRZAR!vs=M)HI48uq<{0@>HCOdQ~T4#1{#vk?`0VeM^g8>Z#)wG
ULz$wz|zvC;X&SS2_V|FV^omX*s?Nx$Zvj>$9Y5(AlsR#ld%;jCYIHQo~PPK2jTGtyJS9>lviAkv
_xUXIHpvP5vl~v!}WCf`>l5rmaXV-kZ#}n*S);vSlz9kba_P?9PtfY?NNOhWd%mdi3Zid6V!>r$-
eCkv@TnFIy*&V?OhvC%vmTS>{Ep9QZqKx_(VCHkmhHh6p++PRdche}17SFSk(pyk;h(1#(i<F0Zd
xz_wP2tjH#(g-Eqdd>X3E5rJ$?II45H50@NYp9q^>GjH_k;c46~i<cNv0Fb*52*Gv895uCmiop&P
sGrzk*d6MR;9&h%v*ZuKT{~{AFcW#S0RY@i4@DgeGVG%ByXZB=9AXa51EIN!AY-b?k~-BH4<aRNw
_2fz&kLv~X@Q=!Cm#l;m!Tav3~1D!E2Ep{*{FJSjWW9ZYk-4<eU|rMXs;HZ6IxpuyU(-lZnhlhVD
jg8D9x$r6GI=DVd1e)xg9u%M3Z3n*~CWoRPZlD>!6e9fqo+=kbeL@%}Br%9o}U?<JT#}xHVbQ@q|
V)1$<B=L>)Z9o}y?9fT%2*WW?!xA1f++<=3rCq}U<cCmy^w>|uNmJ$!vESgn*bNRnWeARA5EXp_$
NsQpEj0uiCHCs{^c#geyOnhhODs(p=bO%cZRj(T!Bo?5r_?Z4(hCYtEY{*nuu5M_=3%=WC-ii*xW
09w=4^~XZHDVcqgG)q?XZ^Z;O`<Ji8G7}7f1?x47VTD#XGs!VG9Y;Ws|6+ujeehSIumSaIIo1qU^
i4Mjz7uVaIVM)3uFpnlqYeH0|4#RT5WGoBg64(-Jo$$1&S5F0@HmJ1E_^ZBkVoL~dgQZ0-wIt>6Y
nJfZFS+%~}W`smYEG&>!}j>6V$Y#nG{bu@83cD&L7P73gEafDJ2#lG7n+_)1Q&xwgA%0ku+BwmcX
O+%*Od30W^=J8QNu@clxy#`1{NWD$%s#trQp<NEcx2bK6+OP$f)!;dN9~nb^7HCvBAbYIIA|4kR1
=d(p1n}D&oE%A+mc-EjLBft3Os5bn@`yE5R-iIJ^sso=TCrm!P#%abRslPsGl3(vBYAl23kHr8i&
wRkW6l}}$L+-h9RNrY+wHdOx(hhqlq$(i3;$JM%Iqi$OHp8rKjzaYzX^amM{_YIK-)9y=by{0h|9
U0;Gm0E{1UC%12jswjcH}u!3zvfgprdX3bs?gC}pnLBJd+rY%Lu8s3si1nZA)@fD^aLzqF_cK!mz
qj#?saNAmaUi=D3<WjkkTMU1!A2&-%x<yA$LAUl-wt1P1gd}My*26FB@Mm+YcYq~WNwjbmw)gnhJ
Muxp?!bw9?EIJ51c)VixEoD=><D>}FSnGtfQ9~(5aFP-=V=NgcsTXe~j+R7-JhyyW^aV>Ph%pD?s
%;ZZXdaeB6xWt_LoO>b9pzag5tqsNpxnk5>-1USch+0!*WU=*Srf#Y#Y*~V+2(qPx!&;1^Cxi(FB
#R+Mx&y&jb0(^rzqY?c}>Myr1A@#N?<d@B#9laU96Ba_G?=x<%1aXyS-t*9&Tnc240eY3hSBuGGT
B=q8`2^do$&q%scD>KxIco!<S9hFk9Y!N(p<^hR@yojT02+n*99NZC;!a(2EBkw^Pr`ow~-=z0s(
dp2}>R->4KI6p52)I)1XERMJ+&?<G6=CDAvR<sl|zU1^7jff9I&iE)p(0QtF(vX7L#rm-%QfL&D&
v9<xa3&uv$Y(zt-Ye@~i+>*NfA{PWZB2$!1DLt%t1ig*qNYP%t7?}<&Igu#D`i_vE>g*ZT3*ZHS)
DsnSo=XJjBL*}A`SQbvLw6l<Y%+SQjA6Ndqb^v7XGXE>MKdWKFx5VE4vwl5!;gE?<UwL6VoKOq6-
1y+jlLrHc)Ii#YdVli(SRg!PbkV07-=g}jy}((t#)G-_Et(z011J!%iQ+J%${!elrd<d>9?eMA^|
d&?5tztvBc(>oLr&V?~I`rGxNDxt#;K4$hjd8&?#VbG>vALlZf56FcfrR%oRC-<o-~2if*GOTFUz
HGWG6}vhLNl(7ZW8^4i|TO>Jq8PL42ge1o1IS+DyWbC#)~6LOI)p(Js$RdI*1M|O2G+s(sO&7l|+
nwUYAF!CaH*oLI8aSc<Aa=aO`S9sut2hpCn?8MvHcHp0DQfjH_Y_rnRTwOB-jucY16Rk=WD)}97z
Ysz94XZgAV+0_F8BO@$4>>Bg-<;l-I<>pKa~r{InHMTPuTJNP@l!o#Q_H#od2F1T*!MejA7y#OdR
@(D+AS-rtV}kv9dfSc)U4JCPp!^NE5T-vj}^&!4v@-b&$DT^I7jinZyQH)azwUj8sB7DjwPCYi#l
M)4Vota?59OCpGGSQuOAd-tRxPGE6Ix)&7}3V-y8;_r+!fAC=h-v$?jnWbBTv`faXyVx<St7QF5J
H8D`uziO|ad{2QC0v9YOVt5&j0{oNniaryjEp$Skzl3bFcxtFN&chQOj_B>kojj0pTmdvl0coPW^
U%x}y`s|$$ao<V$CL+ZHMY*5NndyA2?d@o;isPK)u2=SV=8c=pQac}utF17T$ZV_+^iZ|YY3GvXJ
;z$L^R4m~cHSpTH|bGSM#;oVw^{}h%T)jhSOs=ERnZ}kVPb(1kPxLrCn>An9(Totb$1ztv_W^jvz
ufAJ3UvC`SC))(syQ_4WZ?!Uh<L-%(2_BK9}<g!*kn$%J6+vXBT(&CELQhc<Qt<XArq&>Dmo4>G9
%->bFE}?5<0K7BNCcw*Q*BB4BfG)p1n`TyiX98>Lki6ldVRU{r09k-AFgJ7`{6!7xl%++v@q3NuH
=o>7y!LX?gPic}x%l~v4mD}6c{DD4`kXg3N?*!aP)y0mt$DAB>n@)DJP%)zVddfEcNx*zSupzFw)
%Z@=!cF?GS2NOPWOXQE0#oXpCL(Iz3C{JPGnv0~19lGOK^L|!L*S^<g)Rkp^uV5$3mabO#)4Y~Vs
Fs)A%iAiycT0*U;y_-%_RUV&8soh&J(keuLXB4~?PsWb44dp+Sm9G>|I_)ukE}ruXzR+)RTvvoH?
|)>$h83|dmy8f2`$m_XCs>N*Q`4WbsuQpY%&)rPk5cPP|_71Nzzy~g(LN$v9Vdql3uqKx)syoRys
qSX1yXebD2I51i{&2nzIr;$a(n%f*Y#SBDvKiHMGh_RvFz<t1rsPTwyuFJ(2_2QE6Yx!iw!TN;}J
xj4diLn4EdJCEMV?PN8d5I@P<bUZCS%8g&9=om$Ef;4!d)(cNqn=U|NvS!7eI)y5iqs>EzSwFRl3
t!iG32upirHZO+(Sfl6G7{nx4P>8Z<0S4N8xV{b6hSiHrme#=IceS@nHEk#d+o|-GQNdDcw4N4GG
6bpIf-w}Q(gu9mvk9PtmMM6MS&zuh&3ncsf7O|0jnS^@2fqEg`aw%otE1%Vi+7|^$njPBt<ElG&d
h_eE)JqKYb{z3N`6gxxUnWqyHpb&ZmKE3=vTp~u8sm$zY2i0wb)03hxy{?^G7UFnikZ1<x{t><Vz
^rt+mszcu><68-`U6=J$%5Hl@$zEnX#IXv)i9tK+_F72|{8QKv)GSetoU1<>V4rw^PqJWGYTI8iF
smr4tK<OcFkH<iTA%4atS1S{&v<+*f$&cwS~wLf&4k!za18kY&%uqF}`Q!h7zq9%$)xu`fIK+NjM
|J52tY^{x1IYZq;Q%Z3%_p~_bYABbk=d675%z$bopVps-_Il}HLtgzr$L#X7u1>%wzm7_woij5|a
h>@T;$)EYfO0y@JtxL}mVNJ~2%}tJoT!mnXd13a6TrM-F0({S*ssd)4ZT>2sFXf2Bn@jaK~a%D($
M)1QOZd3)95lLJM^PqAd<TqK}B7F`LR&6P}VTP=v8CZNM~~=uC!@acdQ#8Sd9)j#tLe=8a2~?{Z7
yzv=oaCg8P|%#X3XLA~q^ho6qK~|4;+ML^89v1%Acp)xtmFJT|nZeN8r0wMO0Lj0%j9>K+FDZf96
~%f@%XCEbl-H$B>?2M|0Bx}7!6Qh>))vc%(Is&<lTp@mr{-0M}5NwK275|#99`ZDy$9Y}wx%Xh<@
JC@d*+b;i@TS-+|l87l;({ipNvY<KCBDrSA^};fBqWmp@kJr=eGMeULLvVRCqBoc!)66l+(I7NR@
pc{GV&0^&V>CjK2VxRB465V4IbM_<_If73(NVg$Z902QV;EzOK+bE=iS4JK?m3-3`|Dt^8{_7iWN
9<tEQK7EahhDtFf7o=uk!$EPTFIn(xgYdB>#M67KLRv|1-j!gO(rTRSO0VCByq%2M}t@>ono~pRy
#%CED`+!esM@!QYZ+0r^Q|m^5{5n+Dw;hhSj!Iy*$c_RZrsu;v4kZJ?o2LP0K~ixe=cxVc(R15P@
7C02-&B^g7S89%&_(<H*V;(2(zoWd+&cy!wUZDUM1z`S^I8%^mM5X&MG7fkf?qG8{W86d&sS%Ow@
Wa}8g5wwt8LwT`4Qj~Dybc8Mj-A)S659^LIbkDLJ`puJTSbm`2X@QPeeA~^QrZc&2!}uWxE9%3HL
TBiG`TqFz$>{9#9~cLHulM-i@FIPE`eyX{`20DhVC`L`Z+?6|dj7*PrHSo5I^YNI-k-ice*eqp)y
bRh&ws#IkNL&f$@8~wUbwG%``=!q@b&!o*(>Pm_~ps@FYx$a|04b2$Codmv!9=xo@2=_H2?1X$@%
+}6MTC1%j;)vUr`es^Maa@3I~`m_Vi8ZdACPB!T?H-k6)dB|K{X{^ZYTb%&WK0|91Y%yOYuBo1dW
63$}<bkAFIO|Lpku^mRatrFkwbGPum+AKyHG`x*v)c1G`LzrK5Wc6xsL_RZ+*)m!R0-0QG6;2t_e
9l-zShXvms!Se(7{_P>Alz|7mZ_ydy<mdDE$0HebXnPoT>8D3Od-StUKac3=fPNm+5Bb9R$Jw_{{
ONY&|E~PslmGYR|9$!Yk^Fxk8Hbdg!RT_COedpxmM6H6M##tL<ebV!1*1BAgA=lxQ;ctMm*?tG{P
-3xGw>{NbC}_aa%LtnATjndtROPQ_YP{x)BA@HgPz+_g>p&N=sxxwi3SOUzMzlT+z_4QyTOwuT*Z
qh3+z{{{d64scy@e-Te2FQTy{LgbgQpEaqy4ugsk_Vka6zFbGsz^J379eug{*fIMj+*U*jd#TDk*
diBF2FB<0IBLrRqA_Gpx(NiiCQ=*!`Tf#SR8=~X*P=OhT>OYap-)m=Gy3L^qgTwTSB>X-S5Jb^6}
CL9W0_LEN^jm2|l(!FsS1v4&R!F5SyRqE|P)f@VTAJSY|v!o)3+15Z51vrNJ#OT~bxpmQCUJgRO0
l&+FPw^sCapc(C6&9pjJ&%?@4>XSHl_J?-;$V$5#DU=H$15VzccWrW+-WJM#D+G7{$TegAKaH61w
*qWb_|j3+Sl3>jP}uCBls6IxDG)=|Ixn!^030{;U4Yo1Nh}4Pov>F`qv`aE}v6o;&GY-k1F_{VnK
WEoU_Ag;|Z7RSKyEZ#)jR?JdQus^?`gfxn@^rDa=xNPkbOfeJa4==G~>GFuXOrSL{$TA`HgVV~(}
7EKdXsTLQjy#KnE2TRSdU95pBP?p9$Ofz^L23qh0i-wE_?OQ?SXlgd{!8O=@INNkqJ?sA29>^E&b
I?T{++B|@vyXm3yQ!Jjsr;-WY<Q|VEgYBvf&*F;^6HQjDOp>6Dr%&rH4XKA}g;*t#LD0<L7=aTIj
u?1{C(UA6ecOVk4-OytDPhcCv1_@7>r@PlHb1}yrrsqwkrdSvK<H846b5+X-!c<-O_O2eP-wU{D_
LX3Xrt#%8>TUUy2CP#!czxJqr2+U&?X2D1vbpX4?ORF?Kw}wuiJ!E&Oc6UUq~f^E%GD+fBU)2V#r
LCkc(aJ4w*>58oxN=0{%Ouk&24AyK^=#@bXzlwN&#Y4y*(+=6lc>e8j1eMq-2pOch};$#`vU&IAL
UQj7`~ayhLLh@ewS*zQEmpnF7_iJ6x5PG(}JW!`Zg>gCk7kWw%;0JfNHpYfviDr=~LzIANF^2=+h
EF2?_+MP`1pk%t7IXpg30nLRf!qelX(1mI4jcU6|o-E-%<-6jJKHGO?8b?<s0Av+usfGJdv#lHkm
U(JHp^lt5kyER#Z%1a@s>4RDX$Ddi967nvuWIf*X=-JrR4<-Tc~`E=h?S_Fj}s-#b5F5X4%%s2t@
tyMvu;HRW0?W4n<G*LZ!fc{+R$_;c*ur{aQG#28UAa#N#ggPFauYC=l&}T!)XI_A8o{Jjn>V;QEv
Png6IlYkNzyOnjJ$>KBz`#j8x-dGy<ztJ|;@Dh1TVWUVA`q9;ot`SZTSOwoGl;QdS}4ntmgRWvOr
!5oC?s!4*`%w0+x7YrCmg5jN~yw4o>tWc%WZ##ocBuVO=_-pWGI$8NtKe7NZa(ZcQ{Kp#Xa64$zG
;8#QVJ{QB*FToZ>c<uR7Pll!65-Be6Ch&B18IOp8De);)yp8VzOguJmIgPS24@PgC!r9j0OzZ5Nz
<kA^Z}BF>>gcl``+ONq0?k4b|Kan^&Vbbcqqxu)#A+@2Yqd>HQFM=x#xx}k%82P_MFwO*s3%8u75
v)kZql19L7JP(9SK(sIQn#>LVks*p!UrVz)$a`X9+Gv$BZ?Y%EC^VAHR{B_5qL53f&o9sH}Zi@my
jSm0xJq(*e3KxM*e2LhF4Ny};S1^pNjzMhi~U=^-z}mV6XI5|X$b6}mwxp~qGI8e?|g68RSZC9P$
FAzAU3iWjR>Ss*VW!iwr4!}&L2_#sxf_W=VN3tNDhL=^XYZ5&Vr3{!ffgtD-FWzq~vw<SJaAk4gW
%vH}Ws^CGqIs}2HbidN5T=h{!W98c*VvPKo8Nb13np~#@LDd+HqjYcMXs9q>%t+}!=~f=L{(UpJ^
>+NdqWM^&v1yYdwNdgEI*O>UPk9CL!UhNTcnaK>i1<CuTMhTW@bWhq&*I`Hn^-fTo5PVB8;$<ce{
A%q4^uN}1)rQ=@y^6o_1x0Q`gjYq7`7^_LY`kubx#Qt-O;t<`EqZV#a^dTr5+XRr}KxPt%<D4Yf*
i`se081UFAU~RZ6R@I#oM})EnqxOO9=9eFCp8c32?s_lPT!-&3%TMPB$C<9ocA01$a2{ZyK=qj*&
FEZekwqQC-=D^BTE6%<WC!!;u6s*Y*8S54}Dsd3s5sYW+*Jh;Q{2KNXD*X#VJNB8Y^qwCgy?o;m%
t(>E*uA~vY#=iv;w~eh#?AMR2VrUz>G}J@%YQ%&H0g;f4nyDjxr=*obpTeJ2m{v9!>8o^66v38kE
t>5A$GxDFDVzAPf98aUW!vV*e}3~!oV7@MM=`j_P(y4yQ~<SwN%KsufG`MT2;6W0dK4U=n+;enZb
*dbZ<qiWlZ~brr(n!29Gb8XQEEB%VTm7X&N|mx03hhEvo!l22KF^w7z-PH#v{n%_+y3lBN<5%1IX
hi2hICvTu??1HdH~YOkZtTVtUIt16*FwW+`{=m917#TiFOC7Ndm=B?OX^j6Pn5OE$(eoV1&g5+jM
Jc(4@1(|L<75~e`yt(zX9qlI!=exHH&%eh7D5D=4*;?Tnq5P4{nanCaH*|nK$ELGC_#)o*<;=sk!
cV}TPHhCCN%#f;sLik*LzxoEJL{Q7cKDdK+Zg&1se=$|n`azAq$%ie=R*ME<Li&sYyoCBtQ^}QYd
}S(;agxrYNwW-PcV25l{Y53|vmdscUG~IkxXO*l?zOfRf2@RWqavGRs+J{N?%IvEN`h(C#iZ5V)5
--^^DYU2Yu5j&EcV%QpJTFxFbvB=<X_8*+|tT2%BbtM8U!l~pdPyIHU2GFe7Jc$nl>{UAJ$;;8ac
ewn2#=NmIOlvmaOZVLD>**-8yVqYH4<Z{uK|skA{yr+@!DdMOYG3J`T5E+bW8w+Nu^^wz{@PaYjk
i)q1yTI}{S$lsLnw4IUl*k(w0r-_|eq%8<s|rPQ#{GS_y%s074}l6r20g2EtM%o}v>PY#Fcj+nIy
A(K{TE8xk_VZc}FQ#LJyEq0cb#Wl4_=GmG~ZlZ;s2Ls(R?i9<gZ%cqvH8Hg5ZbVeSlPZ>?vO=XTV
##Pjvr&0ibt?EmTDRBOxU)JGYrSZ5iZ;&qvAh~|C}#;E3>j^1vA4U`?d<mtKd+r$bvuU`cX5k`YG
lf_yI0bN0!~`t37sn$5Kcy@?>eeHoGKX!UFWIAchudxoAyoF3Nt3dzqF2Yr5aYyKR}%tn^>POb7<
P9cl~G$e`d-*UAs5Q8zpA*)(sjEMQPU)Wv9U>=1|!{ADG=7_^c=8TC-Z*g2>o6D(n5oUAVS3maV_
HuY@KvsAs>fN-@4MES=NBUxNy7jt$VaTRW<%-`~jEl+GqPkNyZ_BLk89X3QRkK1moF7;htzJfN1>
XIl4Rw7VWlt#LQDggUgSy=v+hVM4Dd1;2Kd=;>4Y2B->{RB7`8$s^KtcXFWA*I_n58t-m%`YyW7(
iLAvJ?j1&N7vhGbiFmB>wW3btv%RW7ZSaQXe)idmj=eqXMnGU8-|CXn&UgdwLsMF)frdUnZMAma3
n^F@aJSGx8Y!~zg0{co)ZQJ2|dw?8)^l64Z0m|e9i=&hSzO!5tcryaY9KR-4+7EnxXI%KdW!Uj%~
Hu{OkA5HpOw<%sy+M%+?V*bq+YksY^GX+N#pe74@hk<gMASNtCJR4OzoDYJU?9@OQL9N#!eK>~U{
#fC`A7mU`KIcvdyQ-~Pw}%21NlF5^|kX|v;Kw(-#Xpr<X>Tb}_lnaqdJTH~!}AiDBRGsqX?;K)(O
x9ap<&X}JB$u>j}8MF_Z%P~LwVFMps!OJ3|4)p{EFq`3a^$Ei_v#vInwlDo*3r5!fe*@)V*d$xR=
Fh<8GhnhkJdzEt*n&@BFwy8*&UX9%1>n|M{aSL>cGR~@dUI=Tl=#=E5x$7pjPF{vJ$$Mrv|e`i6x
yorIz6gF1{&FJ;A^ut+;Uj3>r}z47XSa4^2gTYJgG%}VhE0c)_Pds9WNGqTB)P?9KDqsQRpfbNzC
Qiv#CxWgtaT;0+vvqRl0lwW_0a+Uun2(6QRyh+pr;^IQw}8@M{#e)#PWhuC}JRzXsh$YumFtRjcZ
j!_&{px0PNAN~fgZS3OKu$*lz^?^@WsnpKzP6n2Ay;pA2EcFe8(pnsKH<oRmehvDx+wPAH^{und7
VyhT~r=m#po*XY1Y!%>K_Lc~Vx$CZ&YDIuQI*%qWUm01Qt0Ochvz^o&KI?+sV=P>P^Zm);njI>0T
z?j=*TzMcIUd9n3UK<Z=Fp!|($j{m4Q~cHNtbr!nTm<DWRy>ibZ1XA+}HZUpud!=(o&N}V}5z|6c
Lg14C={lP``8@5~?ZDX*g{cnaq3tbEin_xL@PJq!;K>oq>Xc1+ccpRt9TM<*J?JR>6a7#sThlo=q
s_Cl_8812LxQE2Em-fK<z-w?RK0ma2_pl4*sdtFq=Py)}kMEqYf`*EYSVr(PBrD({4<v*qY$gRr*
V<G^m#c0AasRo_#g#ulqW^HSy{s3aW<MWzzv?v(wfUF$6laAS<h*wQHvbxbNVhojDYw*&tgPP`R1
yYo#G^L`L|c8%mo(g@~JvdEj1367kJZA&}36PFgOk^6H^GbyAeSY!nU&0fwzqTqB7*`!V>q#PAjS
(w>W5Q>Y@U`UC@o!QcjD09#u#d~XV9}PR^Wo1fpJ#V*f&qi<eNDZUy*n~Q@-N-uYS1x2XA;(F@U%
x|Z`Ovo8(h>YM2wjzdV-QqY0n0lGFC^IQdyWYZDD2psNr@<fSCDp`nQ8#-dN<j|k(RNkZ6+xt`7O
tSTO`*b4qa+RgnOS{n|#A=)=M}RGqyL4rdja(B*;I;)40eu1=h=VLA0205V-ft6jL+i384M6X-o-
w!e4*Al#i_zTAf}mC}Cc!HD47s8O7hz!-1z5WAN8s8*L6Lhe2^LK%a>fCu!4jJsQa(o!=yL39i=t
wsnbVgrMhS-s%4O>qQD5gi*r+dyiEC!mM9^Wt05YJYHa&MVe3WF2m$9Wctdfuq7nV>>{PqUznW=T
F^klRygC>EJAL26-d_X76-mNg*kqQK?i5?;#xA^Bow;(I?iTsftJ8mXh)k6nWCg%IBLp^meOO4tB
N}$N>>yO72`C0<Opz_Hw7czwF%t#G-zL4-qTxz)z@qg-TpAkDRd}D`lNMJ`8_FGA_Y#2f`2YS&c{
f4!Rv%`&dh<^MJr>>-hxpA?{1<3Q@EJqExZ)4{jxZh?8LViJ(Uxj<!JLfSv4gSE{==h{?n>PALEp
prDQ%T>g(4ztQ}NRaa=L5f@D-fw2xB>fJej~m>ax7qe1{J-h4E{AM@y1oirL7FY9rz)#Colj%c+I
4N<hqF`x7JCW)`~MqrTJR?&l23pk969r#7qBn5`}0#^_kyN)OHHO*SEOzI=74u8Z`8k1ZP?f8Akj
KUXEuwC^9gv}fM1p^w$$9$DrRW9eNi<IDt<uPn~9>}YoC^s|bqCZzyM`06}0GtJfU8LQ%OfiTN2p
1jxNQE#jH|B`$v^#s9{lj2JcJP>=<10!<9CX`<djaNmy<U<bJ+1zMY62E|$^nD%8|8(71wpr$4lL
ad$FJUwetdI!el~h{@_zIho!syetpmLU4}-ln^vEOsJ9*<=5@`VPpDh?co464bEuu}2kZlJ)VxUQ
tjT#dIkwHA}H0brk$;-FzUyq)>eRD!__tdFQ<RqBK)7vEHGy?o2pC@TtdeF6>q%rCM%=a70AK!Fa
o(AJ-beoK)PGi$xIS0xFc;r5X(Z{8SxVK8}E-KqyRJOaQYIjlH?i9)6^^H4%aWuX12TF;@{V|p5E
=qM5rml6eQ$}!g24iM$a>dTu_;H{<v?&uYWhBQa)4M^pKg5%rACO<Olw`?BW$4stG=H-qV>`*jDO
p}}t<$y8Hn+b~l-E9&x{fCm;m@JQ<vo@`aS5w@;C|FsmDvbelsMcp9m8LXzLy?yL_126ZU-Xc+)4
x#D(8ljx|8V21R<Gdlb}O$<BvEm{zP-)k32YEg~)IlV6%f>e>ilyruYM%V8G8Qh^C`b<#8WzS410
iXj`u@f#R_2dh2x1UEcwNzNQ0u`B@#5giybja`dMz3{t~!hZz#_pwbZ?CGznAR%EEcIjb_JCWWOP
<>NRtp*Mltx3hWPzMJu7H>R-27Ay3@D&Q>7F^3mhg_<O`vbiW!{s@l>$sWSFJxRZvA0bA%V$LyDk
YsMz<p(%TkkO4a--Zek=4U|4U*HK%W37^JDAy=vb>5sVQ^2UUEuA1ZYviKa)8rE9S`z1Nlo(_l(<
J?P#L1)3k4tArme}uoJ46gVY4c<#eXq`0r}9m6WmQB55lto>AAM+K9xlNO2(m-An|9rOouWBy{{E
)?w}{Wy`Vcc@wbQ0siIh{H+XXi^jIgBSUH3(s*GqE$B2Os8ZzD)Ut2;}kCRnJ%3*{oRd{oLHAF&>
z2y;oGnpnC~OH%>PO>k_hTN%L9_pgu7e|&#Z+UznEtCllF&i=$qM(a=iGdb+loHeh@9H>d~<ZiPQ
+Fx=yafZnxb(v+-9hh_yWi0}2uln3xwfP*jOJIu>j1&-VD>x{jU1n<Q_pzIo_Hz<P*vT{~i3II`E
~XU`%hcbbCfR@)I|qE%C*#10c)|;C<R&_hY*UnW?>8$|38s4Riu%dZ1i~zmaS>YTT$&^Bm$J5%cP
)jNt6yPg0?vc^G#bay!$X`G6wTwgmlVKTX>7F|%?iM%Q(E!ln$*8)i}B$BI<R8G0JAhKTiryraiB
zBTXs?@1+aq#XIxmfDmv-0U=r0cB!z_>O3!8^>?Mi_v1Cx!=Y}FUDx1I?kY4}<2xtudh{1Xhp{Yp
_YqQY}3~Pje<2ic=r?ExFK`z2DW*ShfS*deT5|8d<@<Lu|Kih~K5MC3O{ce#Jr1F@xOXoUf0^yN_
c*^4Bj(E?QtaHC0j9{X7(PCmfQ#%1T2c!oBo2XV0Ssy(9StZ8{gH(1Erm!Pl+D(n~AZn@h>yxt|f
CIBJiYE<J@Btj+58PZGfIHiy&tz7Xw+EpptZtF(gdDg?JY#&GjM1@HCFH;{^W-GGCJ;RQZZeq(9&
#arh}hYPABOyg)1+HkM<N0As?6w^B!rT*Lk;4oW2~zXgrNyr8;|S}$hTocM>inAi<7gHS0~TU9Rg
IbGNq9SEz_$cjpGjTu6=Cg;WmlyMwHoEvkf?uTikry#h^2+od7M7)w02>t@_Z|2wc~s+#x@2OPWX
$Z0zSW%hF4|zF5YruR{%Njz@8rBTlpBanH7<6*Xa)ACpxoIUj~js?6_<UJzNtPgt1rC^~k*DYbNk
6sh%zTUY@_uq)!rJZRnX+fVSe9h_x`b|EQ)*15g#z8S1Av_sH(8ib!HaKoxWAqs#C27w)23^PkV#
5dkWmQ9dWl6qyDWhy(e&5qc(1RUQYxgUXSHpO+Sd(}S0+)qid(t%%QOvCI7hJ~AP+7Q5&5O;EX4;
a&iIhZf^_LmiJbAF(<fTjUMcb`UHrX@xTMX2uBs1&af38sS{XA@@tW7Cn9TZu7)>?`lrm&dU0)VL
&j!397Sm4jlzH$j!+tPwn<4!BS==*BH&hcQbgqkFPW#sOmtUh3TLc$WuP^$r{EwL7M%m1(NGrm60
Rrp#hA4In-x^UztBrmAZ#hF((~h(NT1_VF~)1^|d4*9_!cSG`-AcQrTTW_{FB=qeUUwwH6vz!|!{
P>ve@f_Kb=cK6EOHlzp*c|jkv_pVCknuXz<YJHnEZ_3CTUrvN+k(!i^;zVqNvk8uYYjj}ALnXfXx
1pqy)hbvbC#VI*c_dRxORj1LL_;0XMYWEKx!(<TP;*vICfTF~c4b0*)K<c~t=}yLo#K85y26lh5#
YBQ^3}}%o|N)5#Js!s9LMiGcf}^vWFL9JD3~Nylm`MCK5T!YuMzr~c1RQ{mrl;%?Wg*s=b%HeaFg
b^qg|jD9i$6MfJKivp|dQk($h{e_BF(`&@I+~^VVShs{Eg*F~mY`{bUIT;>2cpq~H@IUEh{@B<@{
WZ?tXuP*#8mh3&LEO(M-*{NUA^WJO5hKvJap^x&cE5DEi9<LP}P{WMJH3SPKpT&_SZB#P}<(<NpG
$&Y&8t`WEfceKgz8ZNqyFx{AQL6`-=)=a0O{sECp@kw|=s9A$&h(R#k!fFjOuI1{W#%sQ5+`{|Yi
E0sZPr3KOuqZ+s^NjCD0d4a@p#ai0ii9*VJ08O=F{a@4aDlO4@cs_dq)`}kZZ4JE#6@<O^R?bJuy
8CBQEoyWb}n0Fu}mwN3X4$GkR|Di;x-)xQy6xr3duXXqMj3}Nhz3=O?vrc8F7(z8sCMKN}D)&M?*
**=;ZC27#sh<Gs-Q))94e=&Xq)XcqHxrmpS;X@JnO5!~;>6#HP?C7IHdnvy(+$@y<mx=VpnVE2y?
vvDNT|u;637I+{ka%SlAGFMawA$8=-RH#=fzr_nhjF&r?INCVy5WmlMuAdWEZ7SqT{23tGAu`7JZ
m$MlnJ78wl%BG`UBYVg*=+dnsk_ZI`;*$2^gvZ<iG*|OR>w*cu)<A8O8}39I-N-jo#&YK*M0VR9m
)7%WN`*Z-&p1fB>0vvXOu~VzK416f1|IT&P~?4o^6u5~^ApRU*G95=v|z7owO4BSbS^nccs;BdF1
Jqa5$6<Vl)>qjkbRNUs64jz6G%pC444vnHK#{fh3mB^QeSE0%ytpG!ukT_yC!@~%*iXuTouaJw09
d{lxYICNi5IgK#1>2G4%m<M$NHc>#LZ=iOq{Bkc<^a!1<Rc#ph(j_u5%DZO8X67o~`v;S4sh7DIL
HkvQ|4uGeR_K~|d>hfPfh+cu?KVlak_o$tQ->Z{;~lj9dB?*sVATA9OMr^BD<^-m}7&raXIG4CH+
FW<a<adO75ENw2Ke^U=7PM097BQstxC@1fnLVp62Tp-gl`AwUNyy7OMINct%tUJIP4)Eo%TNZUd2
I8m;KQyfcx>m%CG|3#L2Z2oKT1kumB!197xLW^<G29E=r54cA1B*HgbDA~<2u$};I;OuX`TNPE;5
Zd5M1NQE_mlj+(~4kP@m;gzu!~RLpB}$*mu`krPon8aV<|c{x7B0e-r09rKUI0g)%OPzzG=X<t21
r3aD@D@9USq99ghf$<&7cI>VfIY=q26t`A(@8-5J$_15o_@^tpw|pTjcHA)rC_8+~Qe?ejac&FQP
pSUCL5?@Cqu->=W;x{#T#6ljdl9Fojn^Dpo`<q?X$n+$05Rj=M^%6j4R4vG}%*_4og3&7skyWa~N
hQ;9`+p<i<Kg(dL8T?lemUt~|tIDW!d3)e8Dfg82tIE8RPmYTfpX4?d7lypLccRR(@L<4i==X5FO
RR$yGA`kMVW(N`;Cri!Msr=Wi<sulrUiq3Z&<qMQuFaR8f%&Z7S4D=z!MJrNR)U^tMZr=rdQLJzM
~?kPd$Yu2i>84?In$M_~7UODU>H&e$s6qn{BFFZFMVnKWPm_LusYN=y_D5vx%Zl9I9VM+zD6PN?C
>knLm7LD&)G?pH}*lPt^U>ucME=j+SdACEJFYU0t)gp{9bCW>po?<bl0Vr01_t`L>t0d<USE|8Aa
heB+_WlER?VwE?+oI2#k1b4&ZDu)7k=TLdl&5G`o8y|PDKVHM;re!D~e0`<Y-&`amVIh>tuzJFE0
`OLHF>YA_IOVE*bxpQNm&9w|H@7wqg82brbdzDhfQx)89dz<f~VL%`mrSZZ^1ZK6;D#z9=Zwf~HN
ts<|OCM}$z`r}gp*qg^c;C)}y>zctYM5v7?`@q-<lG({hQVSl5C=})yx`Su)Y(nkd3F;~K28#PhK
>q&6D%BHoh=1FXp?0*bbEn@$jsN!fKZJuPaP#U-&xb$tlX<MaRuS9$E(_HZ)i9CqX^A)r}r0VN^K
S`1ER!+-nrVsE~DhjIh#4=p=T+>F9%{MI;^siVT*FqaHU9!*#aN9rz^7mukugoX<5wJ`^lr^dStB
CY!g0zBn@RXE1LEr-{#6{%AJ!cQJM=Z^-VUNptZdbzj2{!`Yz9i+u_T}2Mfk!S4`Jjqmj|8ggFxs
9IftaL4jtiLo+)pTbfnLBZO_$`pTBcHX$H;0nKJBD*>!z2E@A4qmsFo8I>5d3|+9((+d32_(HHPg
LY3Vc=9&pt(?Gotj@@u7kC)5@EK(vjTtBl0Ozh32J!xA+|$zD7<m7z9Xn!WomL>(xXv*?OJB7W1s
EM4Aj5h-v<JG(GIk$O20(a89Fa!)j=fOGS0u=9vL*1^mr9PHhewt%gt6XYeF*}-1hVLojI~0?1S=
6!Znh35DH#4bMcC3=3N_kz+qVeaGZD}hhQtQt)Q_J{oCh4*WAs>ZE88n^OOsV;xwZ35$>vYvV~DT
e2y}){+C_OW;3*FcO0s!+r72uJFtq`OZ&+1^cLgkIK>S>d#{y?Q5^(WU*@p<%nl1yBkzTH5WNU`S
j)G0Gpa_{!&<#FXQqUDil&*Nw<V7~0;|CaKb_YD${-a=~4Ia3?nK(V+%`AH<p;ZH6Baj68hS3Le*
S9HHqMu0`<LPFb6HljN4iMdkmL<Zf!m7v<Q7cT5YEL&fqoU=sI07EB;az^h&}hg=Pz1{43@0OdLO
}3YF-6@GUX+mjLAwX1V3SN=i268lrxZA7yobx*RBih~ZZ-bMhg}<yXkoiU$KFRQcdE>%3^`-$A_W
a~UtwBF4Q*svT`L~0)Fc-sJD~;M<*9exy^`5jCF4l0VfLTg3CI+aRO<Ep+1rLzY`?BrAh)tnm053
@(gO!bdt@Y|6PL6`$*?ewZsSpukC5F#%R*ybXu5MaKCCcNbjT@FCM#<uo8vw()5z!31U1}ccCo^e
woFzU4TnOYfuRNodv$oYVCm!irLE^DH^Tfu-lpCFGB`iq&epIb<jLY69)Hl7uNrkKLNjO{YJIV7&
H3ER7k?H4V0I>e`G(a|MhMfkfh&Pb!L?$E(8Y!4g`i^BD%g_K)rd@DM$#+*@#V9hM`zEEUtx&LR~
7DBT7Y98nBVN1sHQej{k>5|Kb1J-4%aaz=&*>9V0ueL@X?5EUq`eBM<eaAfF5hWuoWRoBIwTj`~L
=<SC2y
