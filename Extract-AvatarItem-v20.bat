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
U0;Gm0E{1UC%12jswjcH}u!3zvfgprdX3bs?gC}pnLBJd+rY%LtDkVC-QgkCHW73+k<I@33D7jU9
E`Bxb=VTn*9%&|<w8A<+reX;Yk&jEgnS5^yYwwR4U*7YMB2~uETvHixGRGCFmaG}X0grb$%?HMc;
@rUdn)vvOQQu~o%mm4Cw@0bVKkW+2@tg?>X{UBFK96A0miUMWhP#ThA{z06=gBt^TDQndoC;6D(4
^F@wHI#B}C@E1h#**oidhtdgbV=;VbIV&sU)_|#BXel4+BVTR=V3Ycacy}wn6okfQa(Ep%bDC7%5
7}1PM;OnXTAM@{avG-k3sxotaPH5)o%s<*PFC?o+^$>C!<>0XjHVe(cfhK6vfXeuc=szRDOX|37L
kNBvHw=^A-}_er*e-OcR5Cw>Rw9!_92Qz)L?+VVARCCJfF<)Wer#$)-G?d51j!sO+dX`?Bd8X3N`
8DHV{~@VUFcae~6OQv`u^n-^yU^x{F@;GUJEc8wE#qfs+Gl`}QJQOQLp#wVQ%_{oZYNm~)Wmn`s?
MBiLyirAlZr5*MNO5pt{MpWVg<Uv2mK2lzs#=0B@c2zyZ+6L&B85>En5e=cPB{lqVOX^~coEz*|P
f;?Z#IxoR^fr<sMf(rqp@lZ0?#WC~bzTnZ1#lTa>WK<E&m}hX5d#{5eEDI-LBWnV>KVONX13hFQA
Di6Gov#0;-r)gm}>7l2S?S3;YU<y@*pwDF{J{n3Qtg`MqiQRJ(&}TogPTMXqpnaClqBMjI{kJ$F*
mpS-Y_cOD-jXfb79}Yi@gFz)yFF%FMLU^jlIrk!YGr-q$g5Z(_|%?z7PBcgBQ_#e`g~R=a8i<lK-
4=x(q&nnttBNyH9e7-TvzhLD_^a(^g1MYmBChh=@>ntI1eS@-JuZQh(9({1lOr?xc5Jx3ThUPn)l
tk?aG+0axt3%Mc}#t}DL74s;2WLKxj-8@{?95J0H8c`*TyjUQ%iK=V1!&IXj$%ZT;9=L%=w9hZQ2
RF7I_~#m{TFO7$V6`+?*8qZJkd!S@tCEmP<_O#`M9_VcZ4UDo0mxxS6F&Guj`!_1r?;g}8gK91Ml
f6Eg^K*E6GdWVR?m&qvKv7j8>c3o1CB*WSyHiHSM!;6%L*$i(->`soa;F?t98OttMk%Iuz}@cMY5
g)q_WxbY?>|3QL)gs%`Q3ZBHK%iZ?Y`M5>3BF9g5@z4IcpZ(;}Hqqm=~i4+=7a64%9*WZaBq(t6u
(4ny2iKPYq*2)~x(4Kahc#6vqk!>b4#ENAm5xlXOzHEx?k=;Z+ZjSbw`jMcM(D_Ok$?vL%be152)
2Ph#)mP)!4ka+cX(TY?7d9?ByQzxV?^ItFVjuRffeuwh;**hWPzWen}L@Eu6pFf*3)A?9i^3hxs$
2rGcuPpn_8#hm;c54<VUSTGY*;pS!qH3el&Ly9Ij^b)(a^=hMyiYcC(xWJ&l8KebwG1Yfs{j<R3h
d6R;!YsL!~!EAAxeo(x>vtF?ut$J?lKIPgN}q}H^~Badah#r<5h#DNzFX#M9T-h<bNHQW4B>_E@v
)==eBK@;rpu2F7E70wuKq@)M;bRAaeTBwHstC<V7geZ;9C0U6%wcVuX%t&p31Wz=q_i<Ej$4<XFZ
wcdINYZpMAVsM;bUbxF~8(7dvOVVJPE#XeOPW{!$|t|oPbDA5xXsXp2(tC;atdW$kp+BHzo4jP)U
@q=M?Y3;aCqJx#?CEop*!(!R>v~7QNKiWS+*O4=qU5=XU`cVT9CVb@Z$R8_<xy@T9o|UChp2EU4S
5y}}bbGSq{j8X-eXk9)E6e;|!A_QKXsy7ic`chzEib#*!c`vimK06If&7W>JEO9l$9rScEJ4?W8n
0T~gHd@eHrZ{l!dub)r!$KmS%V<Z)|H>D06C~`Y(IREYtvHpZAK{*TB766Ml|CIT6Y%eKG1a9<U~
|H_BtD)BtkrrbhK&;N9sdkW3!lly>2aZE2hV-bcQ;CdqvjgGJPHhg0n3)=R10k^YRM>H&mxZa;r<
yX_e)yGH#?+UzCx#!X|}#B-gZ~(!Q336{~WTc9tobaa3Y3xe0SiwktuMLf5Ets&`$zK*zl_>IB9*
wUi^kW5@)fyV)v&!Wtd2$fj1SjWzmIi3Wjc3sOB>)x78vmiEkSUJfv@M$fG=h)J-Z5as6r47B%fe
H*L|s~4Lrt%1kyYCoK6+E5PTQ|X1H!m!q8JuRYS2vWHPV}eel4fwRr6hH}WUhojJ9+3r|_l%7Rt8
>^Ib70dCeEWCxgEp{MN6FO}??|JN;|29woyE(XnFnWG97Jo@+R7l5{F?M|V@;fPsU|+$R8xS_uYy
lq9R;j@6##2%vG)ZJ^Tp5Sk65HMEvWa(TW?><mr%G{YXM^Mpr$D{IjbJb?-e&~N}tVJyh_5*l$XC
&N0iqp#s|TpPKTzkHmA1=&C4-VA2@AzHV}0Ys8kj)m2mjT4H2SlDv6tw&u(}LR@9R-b?FkGiFdVX
f9NzL*ED@KE)x)9O^hX`UT$tiO%#oCQE^0onAJH2sx^+-S{w6yhPsEQl;Sk;X>rumP%d51S()sa0
o6)Atv?Oz_0nOCy!wHT2Igs9olsJK9hICrXJ(utM)N7eX(s6bWs8)1PK+om``$}FMp?!<1thi5G+
dD;fO*4QW{H-tUzIx?da+VmDScu{8rEcjq9T2yq4OQ0l#%AA(Pc~)?nl8uBzHG9i@E^wqpWD5tYO
03tH!L6&gM?UYSXUnST{Vd8Xa=<7SwVzYNq}AouENzDHa<9_cQ&9b%vrvY*Z#qpUqkSp$3F0YG!i
_{EE}7g@3{sa%fHanrx_Qjk?Pj6>=ffJq-HY&an2Djqid>x*Nl8dbCduAb1*dJ8PPy(2=R+pU1;g
?IhDe3-edF*Q+9vVnux=Dv96pW$2MRkp5Pe?}j&bY`8gVUj8w+(zUQ85mOqd<y^&jK|`xWa?LLBg
=IuVnPC7Qucz5%G|j_?;PPlhZ!q_!nPZZpscDqr?K-~2j7($4XoMaQ#MpEgR7aF^{4+c3PfdWMqj
ZlAk>TlxWVX?W5q~s7D`Fgw^oI!&W6VBC*2TCKJI$Txr~CGNwbN%mpdAdOV;qQ+ENupy|B&N7PLs
<S1|0hMbsj*?NqdY`n)Ilb<oU16qOc5SmPWX9IP_z@YQd1CWYVAO&_r!{ohF=FRF*_JTU%abn8yA
v_*?QUAP;N|z^1Nk)1ceq;0~-_XICrOzIhx6)_h>H4K!3rD11hAkpgBFH&@GP!0BwS#J+K|Br{7h
<A?WgnnXBPJP)szQ<x<Tk8T^FZH!h2m=`Z@qbWTDVp&Au+=(7!H0(PvFeJD<OVE;ztSBQmf)<j+C
@&UBiV}{=j?l$$-bvwkc-?XC?^%{Zzj<;E%MbKBEzsqQZ@bxtbtczs7?}iNMSYl2=-j_A-ygp|8J
(T}10$^O^&TG_UZk&2-;7=#pFhXsuDy%&&5y4~&wn_k1hl<J2mIjO`_tFQ?|&J+I(hT``49N&F~2
xFdH(jz3-?uT|J#cczMdaHdj*{xzdSkr1s)&lU!*_$`0^!m_VcsTb1d0~=HI<PIe&k0f=|zWdHw9
|D{7)+UQjbq;Q({dp1vtP@Ajxi7(nUq@vGDC-<-T~o<F9QdG+@B-_Cz|cQQJC^AnVM!4?tb@lPl3
pB<l{z7B}7G|#0)2A6sK<D2JiU&El!&gdQO*LQEvPR~!@z8RgpdP_ZrdmZ*O+(TEZ1Na|3yx{vIc
zyuizdgicHSnPKExI|J{CxiYcqGFPZQsQ%{q*Q(kAC*)=MnuJ(9dJ~Aul`sIQzDVKi!V}-<AJ+^8
cRvzc2qklK&4Rmyz;d7+o%t>0~s|@&xzM2>BSD_EUMkV7!QLa6*>bi}70S@?0H?AK&6-2A(Bub~J
oZ&iO<JB*vbG6-1`^-a$=ydjIfY&~rPgP%fz&-N&Ab(jcLr8uSsH8>0JtH+b@dt9Y?$f&GfL2atm
w&yLS<OICxE%Z{g*$o17H4l5F#ko6uEGHxSzZkI$)O2>=z_1Uu)2XPU*ZoI@=OLu@Q@kw!&q<pz%
NQv?ZAB~bUDMq6Zy+qsqQ+)S4y=o`voCG0!>Aixfx+_OdVMG9mtE+fX{W2eskFjOKghRp0e)1Niv
3Rahx;IYHV8-PuxGu@8O1&MZdPCpvLz*jVmQ-vq+Zu@C3&${@7~RGwYcHDO%R$ID;CET@DPCkMLL
HmC!h*D`=h5=#fyObtQj8o-Nvx5EI1oJjctu3|Zd9y^J1xbO*wCh+BJ6nOgZr|hU}%=aj!x2D`&#
>$(LOqC1pk5t*C9ygKl)cdzFSy5+@sxn0KZ)1X*Apr0<}oC%jcAtc%0_IqYA#KSkRt3X9Mxtc*5o
S6*y#pv0?WzkK>PZeIQ>=PTv(;3bRz+6CX%Vp9*led3R|kz;8|O6+6_72*W(}m}4z1%M$^^mVj>^
ad98%){aXSN6ksSyHyxRVD;b1LeQlBcLKfJ66)W;r1I5FMsrg)5}W0*yIkQN`%RmV4l}fyHV<IvZ
h9#F6pN?usbqpTxyPf)V7qF=v-l#!M3dDjlO$;4>C?JPL+YVgAy!Fb5HvG5M&Ja5BL?2#NwZj1-?
rfCgTse@N*ME3>{@Q&Iu%2s%@44FsdtG^Bt`WE5PFo6g#q69x6H&{(_~mV6dG>LO4e90+UR-HhG`
6-?y!ub@YKQ5=&t%Sv<ZSkferKU1JAo(d(PAF>o(z(Gn*6J7g9-Ji#&<I-+nH$7%~$j<YJe*LnhL
%#xIVzfd7tZq@p73?wrjFynNR2GSxhZ11o`y`5rU|A8`_<kr<%?Q$-j|GG3dTGhs%j6#asQTuzt-
BIuM-!8<WI=pIpKVy0!ilbM)lnRncWdO5W%q!dgIfGsB5XT0dW%13ITZynpP{PNl=3&)6~b|;fLD
48y24v)`MKy#sr!1uT*bYYr%quOqgCrkKGnY6g0&-PuJ#?ciD09i%CYvF#>Y%7O>Wu974s3Rv%Ox
CLF+mV^J>abC3nt@aWM^4WAtC~Acnp&AD)r%)o-j%B|VkK(l<HR5H+*9n8gLax$EB;L6tXokkT4n
(3=7<!*+skaKHZ&ay9<pJI9e&ANhX2}blKA~6%)nLPx&O+-aM}RfM;kF)qjfWIlpFttAiBcUqd$w
RX2%ee5311_W8k<LjlgP^kBQQ3p>;W;*B;QD2dca!R$4BnEmPaIlvN11rr$`SWGWm*1X*Kua0L}G
A>g*t+HPuA><)VuZ77NZ*}k}<G1g@3tJn~!x3UoQvD>c)A8vX<w6OaK&<D|q#I^1k_|*`;&&9CyO
RxnIUVDDjlVRz%M2bti2|Qh0#v@{2N_<KcZ{zy_6OT<?PNVG1gK;6JaJF?ghdVnbFkdm~TfE7zI<
Bq9K3_(YK(o-qfB1Z}GhlVVC@%B`v097%T5VHP6x}1FF-?iEGGh8!ky{xM>dBE^1;6&XoAf42kml
xcN5Yi@j%(ehkY8acsD1N8`_p^rS;AJ)F=Gv;val0C$Zw>keZZr%LU%?NDr;X>JeO!l<rkXubb#&
)E?OD1(0ZRmFK{+0J><Kb(Sj3zddSPLB_9Qlgd`$Jg>H~a=y6rQ#%Lh8ME(UpNo!ePuvfgL;>GGz
7RZZ;u%dd%aQ=-Leux$BeZauR!WLjA5yd@U8wZpD1E3x$p)4$4nKXmaZHbQ;2s5u8bJeqpDtHjD4
nd$P-LEt%SAA5`Sot=H7$g5?#&0m1Cf6xJP&EeQDBasQ8Y;|0GgA6bx|N5mf8Pvly&ZqAXg-!`Y}
({VZInEPjv^|cR9->6u))DSo&vWeB7TqaR>S=-y!=hZv$(j)Ce{q-=5VCOMx+1q9~(XD!_*8~!6&
Czyfg7tJ-2kSKHfqthONq~kmpxZ-BSWZcXaJ|zT6vTvDax-sYeC->HHyRYa**MW>g<=s$TU$S9wr
LmC`D!PSp+~^#;1wl4BcNpTMh&9TrIZJ>rVw_Y|ySkr%$k_#Q7N07TwMKb5BJC?3^3%QkJFD6qie
ic@-31w|7oagB(&s$-h&Rg-#OYMl0iwb9KS5AJZg!9Bvk^*aCQ(S5t!=(;ta`_%hGE9WSyD``Zp@
o#~|ZDT7F`}Je17}|y|4fPPc8ZjY4KqQ!>X6lIFDQV@<r|@SL0G3Tg`YI6>#l|IDizfU3aWCj($|
gSSpE)67*|z!dpWi$aXD!m+QFJdd)DRmF6`E~f5=fIPAPfQ-0yi9h9tB7KW&;+C8xmn+9VP(AWTP
p@DHzQQhbHVplv<8`SmFnpv(B{^00{c)EX}@$fqhLE#==IQ@d)xb{#fDtNJdh`0P^_BLGwNu7nJL
R4OP%8(^p%TnBH<W0+&~`S;}2|Wvdm`R-OZi@@U~g34x>}qmP$6lZ|l=C+#M?#295N(kw*>b>5<j
geg#a>!wHOXrWw|-)G?ca&8ej1jJ;dIP|atL>?OD^0SP5c5NmbOO>>~@gd%|IB+rb-C3B6O&-P*G
o<RE5I$GmufD-45!7<A5AL9yo1MSZUrbfCeo*6Y@?p!e)uKU|kUrx8FQGovRC47TUzti|oTM{p(k
w&So!8n>e^KfG?1wF9mp!o>u5u%?d#!E7A1mS8sK_Rns%6QRyLO|kl3-eOF=@5;v~oe!yh}phn)S
abi+#4-=a_6E48yVz`PZ@{x3sd1GU~dm2Eob#sE2NQjeiRkA8sCxrp=7Thc#HdMh-7E=A+A+CBd+
RCF{CoP&UL{w+@?@TAJOUf5k)Zqv4|tH|cAA5thW1kHhWPwu)k^wyH&!t*)(6oKaGBwcf4T4uym_
CC+ftghvN|q$Z^ku=NYRGNiF~DK#v#%(WdbDgiO0bfFuepfJc5^9G&!lf&V<BWA5a$RzC93V5<}8
1R+)lub)vi=Aa<aZPQKdA6pLn`q(Z!9e$nJH;~W+Y;bZO$=?i8xhs-q>81etWar-STfqsY*Zdroe
I8?*6lSm?yL?)aWC4O{Ef4TEUyL~%7y|6Lq?lh?CoxKJNx~^&ugbw-OeG#UEHFf8kutK?v;e3fRk
2uLgz{bgp(2KyN)Ukr%Fab*LiC39d-BarhQYk!i>rAFRde8sfHEw4^XGZCf4W69Gdp&T|ZjGpPBM
c*X~X7Mv2+Hb%O>(QQGxH*=g{JIaD^#2WB@1KI=(Y+^iP2ATsui%6dO?7p|?1W$W+lE1?Mu>e;WW
QjBj5OXsxk*Pz0iV*~W<){d&`_cyXOrL&37qd&sf$Ux-28S~PiPZEX(#@mP_52)q!Ioy31?XJgCY
ut@3p$;u-ubMhWn9yrV0koYZdivD90jdHfRoZ+&@`&`^og66jb(js1#=F~`zKd?Nbj8<EkGlWH(e
<_(U2o0kdS7~UYY#Tpg+wnR+DaerrGfGD8Q`nohT);8=J<|qEfBSPb;i|o<}WlX9EnjP{5cuQZ8+
HLZxxe<=Y)YlLQiz!hFZa1gKkF~pEE(H;dPr_gr(1FoKTWSw}pVPW+*(x&+6N-V_WSu|N6bNO>x{
dv(MTmvvtHyodeEs>e9`pwyN}VMLlW>d29A-5@jlSL)I{k+TR2N{2gsjQuzuQd)!+bpaP<&rCv54
o>dL-w?A@#GL)pX%XpP>Lhd-4Z9FtT=xIy!)@Q&>CiCI5)_Cg~h^~Co4D!V|IC9kStvWrIGv+5jv
JKHg2JOS<a?DSE*uY0u@Un=gLp^~3%x1V<eZug~tg8*C?Mr{yg3&d=-#~d7Hp!N-`7?0&447;Wk7
NTZw%`*OOf<Tdv)%rG0l0Nmzm{CJ9rdk}-rSlSCH^&PgfF5t<Ga>v51*<Dt(V<Bg|;fZPLHaPfkw
6)_}c6Zw;UGiI#n>M#s5F1{IPX8Pij%07=ojqwH{V@$BPA@R_bUzM{gxZ6uOE<5_7rsY^u`-VeN{
zfF%@Yl`h|a8C`qdR~jzcM5wdWHf#te&VF72{2Ik=HTl`BtF3A7uR-_G+V(6@)vCJX@bvTYZKYR&
(kW^9RS(lua%;iKyB2n@X4R!Rh27v_IC)jP9dj!`=wIa)dA^$WVfedHZCD+fKgQg#*eb^0sVGvtC
&$YLTLn0my(L0o?z$_cS`pxn&Z7y;S4LLn>Ie<WY$r8`&$^)Z7z>x+e1CGdW{1ig*Plh}wQ<p9jt
6mt0-S!UIrJx#PPJic!<#`)(xshwreY#38Re5B-Pscj_qF~o=r5(JwA5tLm|vbfMMNY$gL<+X)Gw
WfglbB38cy3qCiC9^+$qvJ?$>xQ=>>XJXP_Wq0j#aDmBE@*xoRi5Rq)`NaezCXXA?^KX^WS|K#Xb
n%BW^HAl0(zZO~7LrD`LYWLjbAs;qfRZ;jzmi{4e#wM{STsh35D$~&RzY&kmGAgrzTIIx?w9S^o@
)%R4WvBj#;yp%Z!DoKYzk*O5CJ7xcA*LsTs+!&)Wwsguv9h1t;;iz-p?ZCf=6K{ph?tIh4ydQ*~T
_bstG=h1QEb=C0f+J^Q+tN<%#H9sm<o;aKObY1<7FoeTvzN1wC^+3iHmOqzDM!UserGlngyLc}7*
fh|XSQ@B${ch^@!p!;N5hVJS(z+d&)e<Wv(ei<Qp0FFHla>!H?q$9l?&NT$Z=Bf*YD6;KD6z&bOe
75LRV$r7zCA8!14~l3ki1no?`+83OjaZQX<OW6{H<!rW!!I-c7b~q-AVsn@LJZe#^1o7RmL9Lzh|
+;oc|LCX=z7^%9Q7jO|UMX%;*`3G$EeG%hkuf%WoT5G`gL1n&JZ#ng;>0%-qi8dJia@Yi22<zuUb
R;SksN|@Jb%~!=uM)CLbaNsG%82t6uMw>&*VNe_l&}U-BNkaBqk4ExS=Qqh*f~$4EZCzp-A?P`oc
e=m+dXd5hVbrj|-eXmOFzeS}*(AR;j~5tck>(S;%P_eNnZ9z8Z3)RUyGSYZ7iOn|7BtYX70x&|i;
$aM1(J`u#ewfmVUFKn(7{=}xR#7J35Bk{j<Z=@pe67X+R-LNrYI>Gj+*kKrSur%s^Sib(iKHR#W+
nLIRYH#O~FWaZ2~tw4cb?i_w*KF^)(wrw?E8s3LVOkK55-leou;)NP!ch;Gav7^D&ZM@H*j~Gjrf
}(aIRJw_udOyPK%M6fP!t3oiw1zbwur@9`~0Pvrz>Iodo=R!zyVi{qlW|Fo*n$2jF?DVdLo`ucSa
YX_B799ImiAQ{yV?c-De;1O{L<_2%js1QJlHy=&#$2_`LCymC&%X%DawYWdCBU&v)Llo_D%oIJoN
#ZNL5g6pQRrH|M0uJM12YwMYNr550z!ikXuHy-PO|up(lllm&!yoaK#`M`kJAPj>qws|kY*&2&Ve
>|R!GH$xF<<3YmCO0+A|?1@c?{d02lDDC%KFS%?#~t0QP{*K0B6Br7iqUGQw(AR!bOKaQX$OvjoG
I=?ap3j|1g-59X#ge_==Jo2i^AJUV!;sua{&<Ppf~Rnt+9#a=>8xMtLD%LD21`155YA@vFC^AK#p
wpN-y~ydS+rCpWxA>p*Y8!(gusJ@Ux^PTn||L>hqnXA4HqCT>JUi)hm$WZS`y7-&-ExyFP*WDt)#
4SIcX^78Hb*P~}|-<(j~J$0%RISJ<R^ft*kjQ~H%=Sdou9(3&|X^c7m^ZkZ0(>L9gr@?p{-6rFy)
7Ugv&Ve!k9=T6p^l|AS?yXY0i^_HvmF+I7+Few)J4Nz%edCT`98ItMfl^9ye@vyii&EW%scW6=lx
tj_!I*QLT(R>uejKO|ZOTMUxy~`l^ls4Y5AkH@2jtf*C0R0389H?u&EKrZ*iM>qN|u*g>vS!&&Fy
a#<+abHuH#8X_;aXnd5>jKT*4|JxF7XZWj4YVB@Q=D$MDyp@1=(v(T<X@+kwb9w-Nz`%DEw>?j*W
0K}aUrB<RrG_#@7XKhd1{BM;73Au`+s*zBO!9}b<aDgJ;b81QonqUoqqdE7_b712f=+Scn!pg1hM
-Z~w0*LT36ujznZepUx1A=EFX9Q~;agVb=`VTMFJsB}a}iF`bO6&b2<&Z>;5NnvS6`8ZBZ=uIH^?
QEX6?`C}2jVUa$#R`3}3OLJi%;CjWp(cr~Y%U6wKf<FzvWIYPPttGaM~IQGm~%`OB$-=w`2kK7WO
O6Vx1qv>`5BP%7kEO`SgYh4$~B5voj0e;6fml7OD71<8oB89G`R%2mc)4*B?g(tG)X@maq=ki<I)
+DCH8yY4iSS-+B_Lb->Y-hseIF1Srw5%M3V`}M;{uQhfA;mg6xp(rd@Ymr)W-_zrQK}E#kAaKEw=
J?X>AuBIVTQcEODeBP=O-*L~6E^^)Ab$P>!&+X&Lo>dum>2^K2xLb-@6AC)r5N36#v!dw!lCYEm0
(o}$R6CB&>RtE6&{p;iNAK#ypHoFYPs^tukvp+GD(fZT>Ob&ZBXU*#}2Wk>Lx!df7_LrPaoMAFaU
1phd2PU0FS&Km1t3J0^Z9a$X64)XIBL#%p3JywWmzmo7eeC9?{hY)Rb}|i0B0>9~i)lr~GW9p9Nj
6}{&H>-`$vAK#p6~)3xrq)W+Z3hU`^`#Kf~g+7qJHu;fiR0?T!fZ7m*xokrL1k`T}$ER>Q@+=fb(
EJjm9zb@DS$(Me}&>B?a(S8e1(#vjQ;clvX^sCiSn{Vtjaj4y>3kz$^{RRyWaY94OJ(mYq~e0qmf
`85h>AicWegm_+pqNns&}(zDqJdx;`KEE&}GxuFP-$|mpz<QD(|0vf|VVz6FBXlfF~+H7<K!x~}W
c+TFzX>3t(kc%*knFdsAR_a`o#H0I|ypUJg&o<%)gx7>+zguJlsXS)w(z%YAKzJk}p0YT(Bi=J6>
)bC0Bbex2w3t}W)J_1-0qMcOCaM)g)(4M&R>|?gAeCK(DeTCXc2na#h+3-s`sC~f;J|E*;z<J)d;
o{|12<O(;LbMbGntj;?LjCCt6StcAqOrJ&lsO4V|1)l2{~}gJUL0P2?P(nn@nbchg`@YB6c?7hav
yrH0hSskw^f&Dl<AJ385tIP=k2t80#toVQ9kE#v^+K@@*K=(G3Xj;^ge))yea7hX7TqOlc%S%k(N
q<G6#oYag3=xJ}}_5oLDPYy%GE7B?SvG3X3yCqPSNwQTTet3EU~0@pPucgWA%k|vS_8~ZuUvh-4~
FP1Uu>rexm<53*uh|_F&+_SA|MNJsy$7GdC&WE9sD)T#|7ep5E6BZ^tijG}yN-bR>MQVNG7FIwJ?
27m@4_f#9_7l8q2WOd~T}aBHb#5=bZw4z2?GUt{2H__P+^}j;hyvh(L10H0!_3kT@r`$pWfP>8q+
Xe3naYlAvm-Vx0mrvU?nfY-O>v#-UbRm#_ft}=bl{g6(=fY&Vc}++HUzLG#GM@91IDyr4(7|f{bj
}5oFAwyplQI+-KUY4X^GK75vn^jD#fcrg6W{g*~A&Z*mPv&R$|N``^x+E<uU9#H7?0sZ~;(7<)B#
bO;DvcYXlFe11{7Ix^YX{Va$@r=$@>TaljaZmpZpQ-sQnny~Bok?T%?`Wt!@)X{x)SDYF<&1Bg$_
JapEjsp?vbq1O}#A`tDMeLPLH0RSS%H3NCqRqs~jUCqt7Ss%3&x{8I8?d2RZaE2}~l%s~f;2raz-
MzB64JkrHUeE{ay{po>W??v|THj{Pn=-P-mlI)Hq$XvfI1$_6Y=UFp8XZ{jP>FB;Z7AtvwF;KV32
H%c9?6u_lB=2l(NITpQLUq5?stP7)SOk5Nj7PLU6~LcwUzL0>vu~*r?{Vit}vur1o-WSe04K`C#5
_MG4C!u$MHMQU9m|u*+(8Q3MR=F<$*wk58I#UYlJ?g9TG*#rIT}b`>B5EIp|O<+@v|~XcwqO2kAl
*V9{ev=qwAX^t98AeGM@!bc^-hyfxUrD*q>H46#sKKUu<oII)=?Dfk3Q*SBRJiF=pU8*SS@loen?
VLR<klSp$HKX|n!SrO7WkQC`YJ$UFkgu+13czWMRKMm8lf*0-?mn%>UiDLWJbcvZk@}r)&YXq*r9
c^;FhKsHvOgH9S5M}|eHPfl6e?TNtd=g#|YS!QxVi1hCuv){6Yq>h8@tSWMxA6XUqFTh<Q|^5*EQ
-*^JmdROK-)Y}D1fw$A|Xx8j>m9Ij460MTwp91yuZUVX%t4Cn@i<3agp8Se64p4EF8;3l$(%;oy!
(kEYk|6!XgwkWJx-sxJ^gF6owtDLh=r;sOLm#QVJ$zlU_bqMqH$w#&;p5(k4#c(GXGxI(hph#>PM
JjB?BHH2TD|b0rZT9!dNEWez?o{L+{%@j%oiu_<(kg`AGt>|~KwymL{_xmhCT3aV{ZY&AR~Ech6&
j;7J<auSj4OP_wjG2IyS&5jt_X>?9W3<nG)(m?li*%f9Zh$D=<#WZq~!Pbs&><VA<<!pw?4w%`sv
gxST$R6?xx^%0EBtn6KxTJkJ;W76B&DFfox?lpZHBj5+hC5M4H}VaYvD`Tck==I3rS&|TQeltIGY
*n&df1L8lW-ub&(}S=frmUG6nWpDynA*0{KPWowUKNdE!b;Y?Uh<SolA}qUJt8=%dOLU#5u(oWpM
f>WMAYoDvz!G1d@>&1Ez#t&FPU=;d<?f)K?lgvt7ilu)YBKt_j}~bMneESB0`Q?cK%~WtxC(63a6
=5aN4MOnrczQFAQV`YI-IV)G&jBxA)9aQ<aV@i|%Xy>^yO+wr~2MJb|ZID<{B#ZVo4B+mS%>-Cv!
kkux}VN+AWwoNIQ7>wa!=ew`I`YQP0<oLzO`v5+&R_3tR>F_6d{nN?&v(vY4%=^dI%QtUdoSgA1O
PfpR-_%2i(<R92$c$GE%E>#Y(4W907sxbCe$!?mueeDmPPfM`>kjaS1AKYxmPH+qfjBC|4^3-<t`
+ejO)^L6K_FAQRuUrsi668NuGarz4EMrzsRgw3z@iSroTg0y0@Hnzj_L18{(kZ(I8Fr%(chK){Um
?yv?7>ReAg^F?BbL6r^m0{rJLc@lW029Sc*=~ZS`2VclMpuPgS0A_5HzwZyIpz>P(w093ek!2S+?
&$0NdGd1HvQdSLo8dP#SEzEi42cSg0~02DtzeQqK0=dcWP2xyS~Mqe3q`~1#qbNcEt77jo2yHZvE
_v<sdE@b8_1sWqXha@xD{0lr!d4!_xCIcFM)vLFfvR?SSgCa$GHYFtB0<bss?)SomVR5*~wk*@|&
oWqQ2LBa=C0@(gsxm5F-X6G2$~~q1sxq(SljCB=C%MhVg(0u*ohWlGJQ(mB`aN9l66>Iaj7zv**l
AWf_}=QG(OlQ;BBr^sX~Cf18<sA*)O<XS#+v4Ug)^QI@PtD@5+$C~syya|>D9EQ@2E)XQ%|AEL3e
0hdr4y*J~%o+3gt<cpL83@W}E6(TipuYPg(=fP+BQ5dLGs2Y@+BBhw4`mcf!@SQkEe><`18m3c2p
}r<MNX6LtUe>*yn|qvaY&$+n?pSJ&)rsHvc(Sycrzd0;OT>G>;EzU}2L-vKD)znkYA-*_mpq%i1o
Z9py?&c=l1+|vFj?5@P}7J-WbL<`z&uj~<5SOxiu-|o=AKz*<{^wN284rk|^?_X7LKJ#q4y5=kQ5
_IHU?%ddCb1ehQ`!+rV#(qNAUZqs=R0X%&-sZb#7!XKCX}oX}fmyAz%CR-en}X4PQfAlL(g#}_@b
AuWsE#u}-nVmLFWqaE8s=I2ds`<HIkyLgVX)W>#DSAHFL?DEb#@bXp4~*0kCTL+p`!xc1PcdPXG_
5k+GJS{-Cm#}GV?VwAXMYaQ%A|och+<_EBC5RTtPVO@v3&)8`=&3C_;1H>HP(oQkzA~fGDw{cdoX
u%P9GB&Ss8z=vm6}%Yhh*4y&wW*rFUYTq%-bw!jDO>5A<CtNfFCS{5_*e)1@}9vN#j+l0>_Nkdu9
il+U@x4E*Ka_6K<l;#3UeUnWmXl-xAZ(Qh_zRNS>cKCAg!Gdww71K4>Xk_#%Va@~uN2~i<P@q}s(
990YmS$D*2w_{bzOrSqO$f+dK(pD(N&qXF0kQ7%sATSCMkPiqLl^Ayv;u!Lz7TB7pxx67p1h5DD<
?1?t246a1s;Yhd`8(vV+P6sz`5&%LA*a2_q4P(2Hrnw$BtN8rxi#xu5*mf(pPOo0Y=9M$grLd?SU
?{jNJ#60T5miN2HOyV=ol)6$$d2Yze&frII7);gMwwVXU`UUxI)yfh@WtW3A9J!AiuGo2|o13WmQ
<5w>)eLX9@w_ANs9Oa!!rA+bR@_2Xv~=K+WI7(JHU%Jxd!(qvUyZtXl%viZ~a7~*R<0-d3gc2Qmo
c*;YAl5Cz{X$n^lOl^SS8&;L!T>(oP5I<MrvA~&+1YA5-_94Qxrpo|jq?fB1*_vUoqhM1kC_-iwb
c2tU6m&%rr7PYvd6CWM_yLBQ-2u<G|0tMgg9mPJCQeUyGs|8|Xw^X22qb~NVf4Y=^=%54=x36~c)
Ho<#M7ym14Q?sWr?t=uqyII)CyCi+S3irsAxGYj(~@3c$c3rG#WAz6oE21!^y~=5D<J;Oi_1)7bT
>B(C)!0*d)^zqCU>tDFqH1@8R+{Roi}$Ta7>RVb?|^TG;N;vG)<nohtJwL(UkxNI^s0SD02(LmQb
^*NTTLHOYm^PH2I5dFq{auVgk>$vBd0nEfYr0y4!Um3n=D_O_uF+pnt@$gONtW!77!^uPhq9vR8#
#3ij!GAzua+jtb^BV>2bve1|pn(iEq4=YR*9dgQ)$;z6^=C}{cH1hd0K@E4AU97OAEt8c-!=VspV
5mXDUL77TSo(N>Y3upPjWB<Zx2ZRP49?HDvo$OUd9wJ2#~(E2t45uQ&<vV~T3>8ib3XU-#h--$n4
Jk=zF~Eg5yG@>;7TA<aIIJ(baCN%A*k533by2QH6oLkku(cHeEIC>(b@CkR~X{*RfW5j7U0+i<~R
E$s;P}se{WRLPbChy!*z@aIxJ!&nBEc*d^BR)*AZ>O(MWqNpvM|8Y(>bD2)c9s{=WgUyQYx
