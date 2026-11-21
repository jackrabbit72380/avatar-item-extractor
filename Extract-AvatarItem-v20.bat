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
c-ri}3wPVbk|6w7Fv{l}AR=j!l4XUlyd&Fkq8Y!A<>V$qX&H!wB-kXtOMsH--0W}Pdi4uvkaUteX
ZL*TC=v<uv%0#vs=6M(?Zmfn881e&q`2wKS3859um0`fvRFL4OtXhcb{ouB<xQULooDAe_}`0UoK
KQ~YXvj-JS~EJSqAx4a7+)6iy|rC#p6$%G9L$NR_4LmXaCWG2C@$~X%WCrd6NXQv?$W-I+&)}r{F
4I(8IkK!EKt{4d}}p+6am=UnE74#N(SF#+KoC5T9qi1RuVC|M2X?`)9#8&&oK>l0|TLlNU+w8V40
zPIIUprjuYV!an0*d;_I$oUi`t=k_?C&7t8UnVe@-v<PnU=>$g<2bXEt#@>@jKyV4(<mC;%x=9uZ
^tYT&g3BbhUQz?W`Lf^b?FVTI^O#QaJDT8m29uh_WsuJ1(`1%pC6v5e36O&0<suHk@ggph;vqw`%
@v9kv{WS1D;UT;Um#@9v->1V<FAY0Q?kgC>BIYYCY6e)72Kue4M7Yh7EEY?76ABQ`uQG~lpr6#KU
vAZUGbnzQw^SYR_`giWT3x}r^&N?f~E7zkHHMScHjdx{XEaE(!~sB7heN_i;{*?+@$k4Jj1pJ*1%
wP_?i~ZUZ^=t1z*M)EQs!Hl_t|k5%hX{kAvG}QKn<Sg@-}Ef3P2vi!{!zr|=+rnaos;UVpETCH5c
fM>O+yd6AZBo)xfevxHC;K=bVM&5NLb!6mIA%NeNv*PwS?=BxC2xkv_P*0Uro;7M_w^*WEg4dQ7I
rS5}pIS26fI*)qtXw?e39T+Qr`%KdbF5^$wD4@r6dJDtNvjngwD*^Rqm**Lv0H75>CC(7_pu0}+0
YJoX8OMu73YF%`qKyzp?%_oOt)?(kga-C-m!#J>h&V-lo*{TOtYW~|d0sH;(Yky}rb(G+K}bu$oj
i&HK-9@1z6;89mUIHdg4yMicEfq5;Uc>p$D07MCP9`YuspiWUHF)0859Miyh&lp!p1}JT6^F;!`k
1`mXBp@L`H%#pTq#b<esqpYLU;J%_5*o5K<*A?cWz^SteO<8&8*JuCm%#T%m{tR-R2)xSL_0O}WA
}E)i1ane2D0_Tx|d?k0v!cs0#oPa^!`ITT+d3m8090~C)5Dhz}yNf9m`MJREAFm0SlytpRx)(<`w
xp|ux`eRWpmgCZVT@_X<u$%GQ+3ELhjz9eP{$zA^`d=r(QP92b?RU?!XRqEq|Ig76C&w>N-m6!=J
^%?Y{q5gP;lpmXi|ugvH^;9}&fxiPOd`62;C$ya1AwNJ^PLty?BT;>7)Fec)sOr5_(O7E!p6`K_w
XU@YyD^+AD!LA^W-g{<st<dpx-^BcY;3p=>c_!bmw(a#uGq+A2X<0K<|ke)?+O7d<h4{?0G)T7aw
BS82asDt&N|Y7Jf$<oM+=H&^O%YNPCk>cyd2Z<~Yr0AVd@1bJ4GW_Wikkc&^|YC-Kbm{VXld=#g~
D*z@Y_SsSP-5L2uJuaTtZ00h{_CDBPfMP*0I$pJL>3JyXbH64S5*eE;?Mx!)K%h4#rv!xXvNYo_p
A3p8iL%;_7Q+bnLUEw(Z7*u&tq@R-!46=ZCK$t>mH~1zvwEG_4B;!xgakiXMdAsxU%IRfS7Yd$Md
a)|uzeSwliLcl1d<Wr$fLbgwBx(;PLAVRQ;MjjKiOzR|2SI3cWrowLbQDGQ1aJk`kKY>c!T!ckVt
a6IPZZ&Y^9(DW??e^wGURlh<}I8?%V~8%ZqlpDBfW0cq|MuDLgiKS<^@o1Ae;31DNqG>I#3jFX@r
;vm8FLVxZ-xH5^41j@OfEy7_{w5EowM&i_hZX6BG}7!ILLcH-bt%w+s<_H5Wv*p>+QAX|Q*JzpY*
>OTggzC-gu){f!%our~smTbv=edqg8~UlCB+zBdYctM44t_Cb4*01?e(j8(K7Ef1-<Lcc2B!2%s_
#JA;PP(``JI>yO3XuO2+SyUfQ?|?>P52IGEci^eG*WX-muV1g2dMe&3EHJeyZQcU<Ffzeg1k^38x
jg7a0f;TYCe`~o*lz^3+h-P4mH{~j(?^&g`bJS@Wo{93s6bX9acwkLYd}V<LT5>Q3oP)HD>&BFQ}
yhWp4niEqG9*K?kAqy#@RUW&DW+sQ8P9>txePGY*gl>4EO@tg|+d!r%C9N{l^gi@P9q_j-ea<W#@
2_0An}>O1~(~LHtuP23hk=zjDuGW)s{0SjJfiZzotBn4QbGK&BI<+!hFj_wjX}#Zy>@WZoi{J-!D
H7>^{_c;!v8`B-N5pawANceDV8bBPBnm+ELFsV)x=YjnSD!PT|}KW|eICIb>OjJDdpqGJcmRaReK
<@2^xfF~_u9#jpY-vs?m*IRzoP(FkTAZPA%y2$K=2k`BiZ$S8a<nQ)#Q!{&ZMK8Zm$B3^;J`~9%A
TY4NvdjwDf5~K^<sd$QVQ2jVIzzOCKc7fpU^n*<6p6c?PXB)rnznnL;0zjS!zNBx^7{vzhzZCrK?
1DRinJm@sKw)PJWK5MP{<}h8IKzxjB&A=%@UBuP$LB6h>0WHZFf75d%ftpAfG2$Tht)a^z!S%Zf=
r~i-#}YzJGoE;jA;80MPePRtG+qcwju_mQxlGkpa`gx&+8flup5F4iynNDX0v)7dUAJHvs#5kx!O
mZg~c>Xgn^bs6tWID@YwyaX!+#ti2KFw6PFuwZ4^=ua#A;mCx&2`Rr@ubFCFvEQ94j4|d%x@J+CC
%YSyte|F1%hVq}C!*K;vy;nI2xtU$$`0Slzx8wGC@AP@^_IVFg@0~tF>NE=e4SM)YA3X!O#{t0Jb
34ATowgwrZZWL*&*#XNAb&z;vf=D_hGzt`uJh><6-`&^eKKj&UNg8yeQ$d}v;vV?sP56r7#6j5Xg
Dl2i4QJIEdmeqek4tK$bJRODsl)F<EgAIr%;iLZY3l!%*<iUhiDLAf_w+{iFMtQWD;<F+l88pDx<
4zkz38F5IlCdIpkF|oa+-6z*g8oU4ix_2+Y^zO&B%vie@2q?WMC>#=nFmQu=Vz@W6ivP^6RmFtn8
gjG@n!GQHPtBcIp4Asq!w7<Ij@Q6B`MQM2=|0ZxxUpqw3P)$}n=C{Cxrc$y<8$O^%t%;yD>bXMIX
D5pt`I#k$0$z4za&XAIllp>@U<n~C`L7i?!x`2W>HXh-3R4kz0Qq*0tp1R2SRzf;Xr&Fb{?%31j&
*PhA_6hm0;RQdy4vgGg)s?U?t(n}qrtXQQI<b%df#(4mqp{)sN2n?#cK?(Zer%>C-9<G`01&*|03
77SUSWS4T~1r7R?riLp1c%TRNndbvq1)}^e@T)I1EP!B@F{CptYsAk4_9Ll}*C10WOhEl^9O5_&&
ssx-@`a7x#e%o0dgf;tC>S#fwF}3au*D^+i>7(^>)A)*!UiN>DA-seQihRCc0hJq8-1@a=`^v=vx
N-^e*dhcd!J9Ud3Z8FjiIE<$-|$KkQ~*GXk~A)#mwAo%5osYrOayt+yjF8MhjHk1ksfEbjh`$cLL
ra)+ttX!;^-%(#^^>Bx0a<#ac=JCYHV}vu%CoVa4$B$AT$#Ad_(1BOyJHLGR{{8umtAfF;g2kfXN
#LsIHy&}t4XXCJQ5$`EDAaeQ#S1+$yW9SL07$6E`foH=0;oOKdjE9y6}Z=^*138U7bBAC@$N<qh}
#$3pQdFwO-3jt#F;Ab$S#piEUI-m?Ds92>Au;MH?<!72NyVDcQkZJ_cS!DN=J^y(xW0K;$tcR-T-
%zSNI8fAF`IPu7BYduzgH3c!s0;B6J^VSkm#MX3VWC*z8)+us&Dm4OiOhHUOiqWZry%TD~LLE4)1
CJA^OJQc(?5mtQOV$42cjZU;uL!UVStNT#Cdn5-Oxc5iY75<c6zYcj%H$s@EQ=-@dwV!}gcQ6+-{
O{9bf0Bb)X)l`sgZpk!JYtvp8Py2?*)H|psmVMpXt^2y}qkK~B-n8pI$t>WS*JWPDQ@P;b#=o(~Z
psOLRQs<AXlmx7Mgyf5$y`)q^JNX85UUvqW(Qm{WF1}l_-CAGnMv40zNN+<d7;8PNY{*<GYvZV%M
LSQB-Lq#7s;p<rMu+NzC7ad=k(;{BzXJ??|`y+vFaTJ?WcV4+|s5oy@NLD5r6y%Tf0pvM;FWr7OR
b-G%N<)L;X!IdxcOc{T5!YXG~i|zOQ;3^turh@4e(QGgNXG1qw{MslAskHJLDNRA_|grg1dim{v%
;hFY$6f8XB*^xW7C1MPe#&8`3?u&NmzRORWZLRp+?ym6Z$HN&o{`w(W`-)E(R3@_AU0=oT37#ppO
FZrr_#2YK*KUG<i7v*i11X7$)a}ez9k(i{&Wq6-tc>zL9Ile)ZM-vOY8(vL;O+h(lp5DX6w17l)y
Mthw-vtM}D2NnvUn_P-AwaPoy!iP;uSGTi`0-KH3U1Qt8=xSnj$i>F0*Iw3nH~j)?KErm4q!fa@t
oRbnF>fctNaB2?tu10WT1l9D$Cx17!KU`j{DtKu-xmjl+GV-$S{RJ$5YtsF<U{=6*fNPPGAm;c$U
y3VX5(ZAS@gfyqd<>1z{|LA(_p~RZvXxGOBcRNGFg-X1kgp$}{+f-3!5K2O9Qk*cCE0nGW}`M)pF
{OCiO+px}sZ0Y)-A`U4ZExwL}OIzi5Duct1!c;c`v^L!dIO#VhZhC1Z};{2>59XUL%MQEi)!*)Zg
Pst`SyMcRRiu^-oq}G}o!hX@MMDAAm?R<xk5x7nScnem5`oQl3$MYTT3m>UfgK7jCs>VQaPmc2)-
6fW>V0ykolf$R<fu7KE(j)qW&&Z?!p5Wi#&CVVzt}h=QJPL2s21d3iyd|R8bBW@$e)A}Dum?HyTc
@bv5yJ&tH%7rf1NaCv`+%<DH9qXq!)tuFj}I?R$xAM2(I3`Cj3)PG$ilsYlW-E=mydYo9(`CCc2z
7kfg%Lqv*$1!I7*Nx;5X>1%uzoQLOXYevB44;m&1Uh-4>c<g5b->aV2nV6X(1Ulca1po3BvMlFc1
_!$H>Rc{cCh-Ymip#qypSKFnUevo5Yh0D;0Z9))1U1j0kyA}pZ^C?@4<o*Y$*qud72aM)LD0Dc1&
7if$WwxP#<G#s>o!Jyr{u%1gJ%$ytn<-_(6#(dU@ox>$S?GlxqA#bByT)u}7gMC;{Ar|_P%?ukbK
<#g^_~jk{^~@V>%WxZF2`Wy5azsFw6H0(svNm664GtHix*7Z*4vBBl1E9v+x)H1Mi^ym;E?20;Sj
5?N0wcDWb9#Gky}hgH*srdL&%i4Ln8Pj<kK9RUjnDKGug{RQ6Qr4-Viz^76Rw0u-xR~~6Ze?^4xu
@q;xHxkrFRk4tBBcBg<+T9P^mvS#5Rl=<!K|H&To)X4!Qq}dI=OxyTMa<=^3?Y0=Uy*7(RvtNfAa
daw{o*=n)P*CUB<)+JL@~BTsjTqg!<JsHvkzo{k<x7f@&jGweTl<mq#qqf~()I~?>5Dg_z_qyYB@
SgyvU>8|Um3(MoaA9rQ_p%AV=l2i2+FaT-nVPy@+J*!IJt+MB@l1}cMum)@GZ@`*4fN_q!s>5g8h
2r{4uUb5wCM8)~4Ts;%WeHjVeD3jQ{|-T7KSs10`_N7rRWj8uL=kh|9e%=fp7-D{;ldu_!Y6|Zdy
EL!ZL~$Jszqx3kF?r=JB=NgPWpdt=m2N=sg}lO=N3)ek30jULiZaA5rKzwog;bN$I;*W3xO<=Akx
bqhaqAhFbTA3S%mD!-i5y^X~uA)i6u7fwuYhDJq_stY@rrEg59G&_2CmWIn?rFxTnYQ_@ZGTsC>T
E69o?A@?OsxRnOFTRU97<6pJ&UL-xYQ6UherW1P`LVu*khdjI{iV<nj^K+1}*N|4jw6Z==-*-h+@
7Rk^CqjL#@*J7EWWjS6~0l)B$yewMkLP?2%^B7o!ah%~AEQ^GVcahcN#>Bjt?>4`ax6th@DbZwtr
M-eUUS1+n3*aY@s8f|#D(scZeQm+GF?^ZJ`9?MSjTUn1%+@?k7lm_sLN`g30zkh9{R`1X4SV>dTB
2u{=(;5w35AOPtN6Apm@vL6t8rnLJvH((G*pZ0qFRyvzNr!1|9w0e^N{Ms>CZ7`$k`z^!M{Ex$<K
;mX=K9w9}l)I4~7uio(F5@vet8FrmqGbjQKC*rI__<<h+>cQU&)ew&u4Kr}ZykwC1=TA;7s6Q4{L
RU%+aW%lR}3x97Ja-FdWa+go#8jcsqoc2&At%X@vvG(y9CMSq0(A_bXYHN4bd6+AtvYrWRkAZVhP
BT>ZGS+n)WSwBQ-iwSDv-|lg!)Y%%w4X;hoY?=ID#bt(noXd<Fs4LxT;2P})bgb<+bE9!Ni1Dn)y
L~yEsqbj5p#$=s>MDTA5gv#h3n}{&KpdoF%ce>j!SvC9!Mz@6v8BRxcL0A}{hz@wSo=>(|3*Fk5;
!TP;CK0Jbzfi6?6X!MT_$~+Z_(mIx3(HzU6K>GL!QL!JsXokpPKZrx)t_oZ?De1niGt#0GO9-xBy
Tu|CsupMUcNr`OmFs)qi>wXoWwXIJnQ4Nt7=#MEPbk{qO*1PJXx<;|Zfkv<_H|d<rB0*u6cZ9jaB
=4228h3g`ms+BVk(Tiy;-FBNJU{_1r>?LGmo5NMG2%o=j7CU6IQQBajHxk63CB&1?5ToE)CGJymV
Syv4py}@y*t`S4|+X|Mg;I<Wvr|{af<7GU51M)zEPW2@01@8%Tu!n$1T*FR_#B{%hRsjU!;7(aN;
l@IWOxsM85$*}4Vg5+r8wxbk$7XEv{JRAl$Z2-X;TVuKeGQGRl1q|`;e%}d3_ZA)fQZ;3dm;cy;M
UvmWTFf}>B>pk#3s`PdHtbh{ya@A^2Dv>7&-!b9^WL%r^3Jc>3%{{*@gNz)Yn26YCo7ad=+%D4nd
{io4AO}a$(l$d}pMvD6+ciTqk(>Y`p`hSI$7wzb;0St-0E%jj&}^l8xd#Q(NVt)qK=?j$Wy)Hr0h
j-|br=Jhxyi+wp>tzCu8JGZ$(Py9pT%KIiEAWvFF*G(|-W8o16E=udiw7xb*i=(36*pW@dg24Lt?
PzJi$zl&@RawYX|8tdOy>fh-46_&VpC`;-#cz}Ix)AcQN1Lbe@Z7OeV*f1J6!&NJ|H-L$O(jIO>V
Z#N+!g%zk1ASeakC*CW)y9FWRy@4S2Ng)+GA>~^76TJuB2<1zI`je?Fd)+)VHaFe6_}IudAIdK<M
~pX19r5>sJy&h_tJiX4nB$=@I7H*Oq;3&RX~kR<zODZVgwAfGxd&3v5Czk)(^<`)?PcLbp=aj=~(
BuzJfq+`;rBQv4OS?WY7l50?t#^#TjyGo*u3@FvKPvs$RH~aMC1NS$2kkmzJ#|ieV#54`znr_{rR
mm0UXUE)UD5z(CZNP@D{HZ$Aa-HOnoUUYOB_Ld)CjT4~%8%_!p<`ZXY6eeIhYY%1&V1&(YtJmd3`
7v&PIeSm4ga5pPB{}%~6sWVH9>i2>iX%y8#-;>PoIiv;FYIkz|Q+jhDMKD&vg}{!ugYT0`TILJa=
dhRo3j>8H{87Ogd5ZwRKpElUY{j9W$g2c81Q1Q9tKj1@`_yqPBrEs<0>-09d$cVal(3#_EP!X5O(
|nGB_n6h+Ah(Go%?w*E=ipo?)6dlMbkLl5xF6eWb{)0Ia9E)?%$4dW1Ahh7^|q>gGn&S6IK(<Xv_
~d;!dc?Mu9rkGb0az&>BojgQ}$m6*<WE8pKm{BZK7`gJcT_7+Q^?=?L48(JoK$#s?h;0AIBA8`*h
-APhxq2du9+rkFlzQu31>5U#0*gmW!=^y5zfMH?YQIOd4S_^#u4^<p1;+%Oq5?stNB*1$mS6O1M|
v~fPomxc#5EzM-IHaYZ=M2oUjRaA3?Oe0}o?ryU7Jz$G8auoQqqKFTse(xakD0E;^C3eZ$Vr0a)Z
Y)BNB+|jbzOM}hGNpqA+4NJ2o=F%-sMJx8;7dvm=ZGiPn*q*fD-Qa6hv$WL_!BmSlfWnV_xJ6zv1
UrW{vi?ME5rv5SoNh-yrt*|>t~4U<rhzpDp?c6@6`!59TrxgntU8jH=K#6i?E6TfwBqfwnU06&(e
a3lS4c$r}}EJh|qR*%_zPYmU6v<!=e@J^|jM3T}WFYca(<7TgxiQ@!vL=6Z+6x&}Ap8)M9yCeex0
GTvQ)Q?77NQ?t23PvX`eufl%}jc#FGk1!)+{{&y%<^1%G>$<GVH=zslH@Dd?syh=%@!M;*Fvrh1u
Ljq1XDi`WI9v$wffS69i0d8?`zu(&5?`sx@l`5<?C(SOB{pnr2Do`}z@O5ZEaI;7hsjoIE#?xGhI
VWW%z{i$mhpsS=BKCm#q3cDm0-imd#<dm~$$Xl!DwhIxzW@GN5W@CAeO7-DuhY7ZfNMXDI>9N2B`
Y{|A_nHGO*tQrr%N<zc&I|<0R@@?lYv9}n8aD}buft+pHRJ}IlBVmcQId<W?51jVnN>T9AYwuU-?
u*|EZQx&kn2626jz_qKqZzQCV#aE$@N#L?>f}&d+3&KTF4p9JMkkh+%>7%_Ib9e3?tT8Nj(yxzc2
`R}@xoMR2T2^pe`H@$3=B*!V7yfMd|I5im7rMj<gOkqg;`mm&^upqhd5j`lT(yb7Y;B7u_0Vh$`i
@IFwX6rJ6S;$`#>9wL|eC@B81Op?#G?#^xR?grL}RELaE%b?ro^*Wtyr@xQjO=w>QSMk_fmMk#Xt
M<Eg7=n$w!0pBo2zGtZ=sM;s@w&u$avN1w4XC23jV)E)5*=0V=M7W^_n;lUlTK|N!jqzdB0WGTRA
9gaSdX49#k-1OZ;9#nVf8`pp!%f0ubx!rC*v@Egm+FSk<lW_tHb)M^*n;qGoz}vX^l^-s-n%prNs
*%>%Ey@u#2J7nk%Ax6YOo|8d$De!!&RgRuBvCdE7g2s}OPkaj4c-w4_QVtclo03Y!5XiW9>VR<1*
|f&_Ut{iSwmqR2OvqD@dM0UL)o-uf%enGyr6zSN2__G20TR4X93OV>%VovKBIKw}a4SSupX$0G94
D)PGq-dDjfSqPRCiV4mgjEU5$sJPJiD`hz{Q~@W=Z7GSas<rA3u)0!9)h!6I7GD>dOwN*7zEGiw<
l!0xm@_c@G(q>Y?bva*jH?S07fT+kGs5-tTxhsu#aB*yA&CQ04f*%>s#HvYL!tFr2foPBk6`@QK!
<@HG{&V+D$c}?>>y8u-HV}?oaCZMe{+lrxcpz{bxM)E<1yfDVf6Z_@E8dyhji79#;C4>pCaWFM}w
}XXe+?=L~oX6IwCvst?d0iNs93zopZotiq!6?`ss8(3i6_Z9d;(^0y_xR_xQ5Fzt)f}3&$~roSwu
bMbOYyaN~#AEJ~CTE{rvF9g3;E6E&VaP7|AkG#Xu{a14y1sIj9;7*5qfa-SAu5$fSr`8JBxj?vCc
5$u8_?<C{EWJf?P%d7SwUL*pyb>*}BndD;tEsmvw-p=9GO=S!4Xz_+IAItqDKO)nDd>mEdqw<wJx
vLJ*krrL;E`SEIDWdpT<7y-su*?{^KI8`RlG_}PXRD%2W+(S4x#Q+R9e4o}l|ZN(F8+6DLJbebBM
Os^LFp;>vFP_1k8zeGLKQ;E?GRZLU2^traZqvW_CL<vzHxiJTcl;>s_OsY@Bcmc%XI1}`0e+)IHf
U{8}N*VY7Z;8k5oHU&*XjsFW}W9I<R&w{2Pf{{O{No)POQkQJC0Lx@Vk<T0%5xz<nWxKvcqxHie<
LkblSsXqhgfD#AkD!MRBmCz<+kF?0-oJ#*y*5)T%tUp2c<fTk^!2L!bt4+;*>orzm7{?Eux1Ji<-
y`#x07*{Sc7D)y{EocCOUiz@{>ZVg9$)~UuEK61q-ZR6^u_CnnUp`vS7sz3T^H#8&k1))uONZW3@
)Ari!939~?d9BY9l7MZ62*;(?D4X^$x)y5Gn8yW`FOm@3lI(dt33f;<Yr(esK9g=)PmT{NO}rUPS
`mr-1HPd7%ygYJ=CHr3(CL1_w|^!LYebX@`_IIj1yOg)Zb1EOn)Fohm;`$6*b5!p!JZ)JO?^owJ1
uZaSs+?;kCf|&b=F*NNg6+)B&nR{yLw%b+7{T=9+GXG5~Akh{})h%a0)=hA?1y5szq4EiHu{p}N{
#*}uoP37jLq-M@YIA12ajp?QB>8`CmrN?Mi%ULgY7i2nNPZTai3sD8SWd=_Xp$-2>&+Aswh@-f4j
<NXj|mJtR7RJ>a`WS*$A=@};!A?6S-kn(w(f|%!k!k8u|{gebR_FfPgz?`6rT&m|~na`*!^?Hl7u
cjO@Pb(<(q*0Hy<k%6kH-fu(6)f-~)`J`9Uv5h)6xM^mV=XV0QcOGuisf{gUMf<d$}6`Y4prH+yk
zKlG0i-Ty66Ot_|?#nb1xeE&&8_Y!Gs3Db)v@N%OZghZ>WO<)rhJGJG4dWi^_>*_LW75bQ^{sRpQ
pWgS!nLbPle}FQ&e#5huVW9m6y%IfzM?Cj&TJd&yymJ)5BE$`T}%a!I%4Y#UiHZrd$#JVv7F1==U
aQ@Khl(2I^+CVd(_Q20QHm90Kp-i{P|&~*W?g&b#kmOerzSr2{4HKhVyqeV=h^o5xyQmt~SD&@No
wMOYwQdem-6pyD)#ZSRucs%S5nwz5OH8C-&PYSQ52k?XpWT}J%$`>}MOXawAe%?i;UAI&7)2Jd_S
w*xZnb-yG;MT6no<3>^XiZGz3d!<|>b7XCP!Ho&_FKVTm0|sgi0o}yrK*OQ+Eh%FP?bd~xvw_IMc
POmZ-QPM@p{tYZ=wW|R7*^L@O?#%8<TP0m}W}hWMTNj^rGc_#dxpvNBz17QUgm{SpiIc^6<gL{>=
*kgW>Vukl<%aS0GRG{G(gFtTe_m;V^F=8W+{sH|E^#wiPXaS)=0}hI5Wtn3#K{fui@3JgqSUK%%S
6z$~7RkcfCr|6@aD5TV5C2nq|Q<fU_Tg(&C%=wr_RUw>6yF$Z9yB1&+44F<e49QFBKraVUAWHsDE
nSVzn-=YX4p_SZl@ZOyihw&WPh3T|_AwX?qRITEySt><l7B(N&8xGeBZe+<_?HKeOyUhpbf5u2-=
wJPVqiwHNM85V=m9KnQTe0|qJx-9UZ7h{er^^|zDm#vm($=;<%G{_^GcT`sZ2q5i%9(LGb#!yl#s
iKxMcy=nwTBLt0tC?9BG<8%z0>r{;C`d$n!j14O@7erPdbwccOnm)7hX^Bzmv|*V4sI3q1mD!&R1
on>l`nxml#C!9lZ%HrS6f*_nGOGpP2eV>(N-aCvjd+jeF?ClgTKSreUa@W)kPPNdB=*7h(W|jx^I
bbmU1txv@p+9h(G3l84KH)>+_u|D?ZID+&SXo$HQC8xby&c@mQ*W|l0j6UBK(8^?ngF?aNgXpxu#
Bg~L6Z){;Xr<5_I<4UgL<+M~1>G&qclkzB(@8>%!{_}aA)=*EEEgATJ;GVOvf~*!^0=9_);(qh|I
3TkFaMJpZN?1v2=F?QNfZB(Qsw{m#!v#5;Qdjf`J1flfq~eCFnqMqMDUMW(EM)f?p<$=dvLZP<-%
%^78AuS7XeJLPO1%g)k<k)1FENtXgGv1cr{>6ST27iYRD@yY_6^W9N8=(}E2qcnYUM1uGBqqzgNY
NRtqdcM3EFjx5hQ8tksB%-OF5*HI+t+#b<L;>rCN)Xt;49&so|?`4_w9Ec+lPhdfV<F6x`ww%!b-
LQqwxZ^S=pM9|StKtCgLSP6+k<eCI84IEeDTLEBMiBj=u546|SnFPVKY6Qip<lx^V1+H<4Yl94ji
^cn(Gb-H#!TWDTR9$D?WwOzSLi@HoYYRQka0^Tt=T$t^?W1_`tSa=qXN3oG1cMfkHaHWP3(m2Y1F
O-DdMCu@<ubv$ch(8?35;FtMu!v}DsNuEni`J~wF$ypV$H-s<RAG|@8oxmcwL5@nTi`JoLiMs`&!
EM1>M9mBg}X&w5-n8K<seQmlMAB4Xv7@UXoTnTXr%R-d`zEbJFOjHBNjknN67jY+oa__;R?#7;^)
i!KG-|xszaOFVMTO|t_$%rzg{LPB4`_5lf1!_$#cp%jEF~Wq0)AnPv}!9+rI60DfCg9!{)r9%q)_
Ey1dI(x>A7t5?3cnOU{w2?CJ2dQPRt0LVc8&8JzhJR4Q}o)5S9D1S-idQtBx{=sY_<dwzO~rRK{8
>aPcuv`s>jaVITQ7+XL9D3H!*e!t|)V3Lbh=yZz4e{6}Sq%ArSEfYu7FkR(SoK#z@oOGw>8TE>pV
iPilY_}JAURo)T*-d{s5pxj&U6Jzf)23BW)`ci-!x-P>!3&W0C`SPr@C7fD;!~N=`Ex#|Bf01V@5
B_52d!Z#T@Yu!%qSf!!VS%NK#CYsJa}?4;4!Jh=bU_nPuWgc+y)`(av7zj@hV@I13ALZvnSWfbn>
)wiGKPi+EG3vDFPv*+QXN@!$8ht3(11x0CT@j6Z7yq14$&uumhh8$=s6MqcLhq`IBkF=nYXQ@FII
wB=G|6GxJ%(3y9z&N9Y(6IwMNvl;I_qq{TR=_y*7pFrQQQhd$1D1TsQ|$*-6U;a9`Cbb@C@&-ZlV
dL%0B%uIBbpd(k48B6+n02GvHp8U`CUUHbCmW6i82Z_Xd=4&Y|0Gm~?N?(pE+6JBA%+6So;^AP0z
p63@mY=1G?at%et9sCFI7+Y|#%#{c-ZF}ifkmLn5vG!VyQP%3<}Tzs6OWvho#I?9&E4GQtg=rfqn
oW7;Y4q=qCXb#wG!Z%Mg~=4T4y}I0u+Q6DF6oT!<MQ9J*;o*3GbnHzGx#FKSj4l!~xs~vf0+w7i4
}hIER0e<!tUgK~FfG)>}5Rk%@t%0UQ6t>3e->F&^c7dIh1#4g=L+GKqA}%a88iT&P-TaLW9+I(uO
sK7pQ|KBVD3e1aPuWgOL1HeCg$FaC*a8re=U$mlT{LQ>j$q@N36(nYkwY%O{~({u)V{EbPFkk2Lf
-W#TCs$iD4iO^^Z0?t2_V>}>yuF5g^G;oAS&<P_1&x&zCQPde)0f{ZXA)@@&o}>$D)$CgLqzkTd3
-tAqEmBGAwZy>C)dw=00njaXmMFCi?k<GGK!jBanb4AL-U_ah91|<9>;{=0({jyW3D`1yjz>BP?v
>X_E<wn`+kbq6&z#1bwKql}EbhXLkpHE8j7yMTx<rlnFk@V50qNwOfbd7ROf<|_2c9akub#kZN>_
%#dsY(^5>YYO>m2TOf;UL@(#50=70VR~Z?NHM@9WHY5}jHpIP`;?xVV|7m-;(d!l*BKp+7E6mEvY
urc?8kBDR>XD^uw+wS1nPzIk!-Gv!{X9;Z0C(+?-FM<+jjIC*n+`u5EkT9};g;5jJ<52DeC&>HaA
oD>wrBPC7?eJud{C}j^5a9qEPSv~>BcfsBLI}E`{yAIn@aKgKZ?|(df!Al6t1m)h~(32(dx%x(g1
Y8MNc?oE|Si+vco80Gb-+VYeeRJ}D^!oVw)8`aRP~{qGVeok<5Xi?@r$3#@$9Jdi&uC(2|9Sdu1R
Dt_{~L-;lVqe=MFPTTG+&L;1ps+tg35JT@~2x69+a1wCT(?X&-u>(_x|MhFVA0{be^5Q;o>Z-1wZ
9e^ff-sIQ#{syW9EwJbQio^XSFNyAMCWp!OV-Gu->3Vns$k1U#1lr-E?AAXAMFMmSYGu6W}z1wvN
QV$_&2{1LM=W8)?96O=tx<yzeyyKU~Hiz}hbE?939BNlqi*wmV!^8`GybR@)qVFEPWiW4K0GDg;o
>B^gEon@Lc2BkZ7Az!g>qeEaN)qwN^i-Grsm7e^j&{nW}s}E09IJP)xEF*Tsj3_6I1@74bpZfed)
mZ2GoU&f~GwZoVRt^AI`G5+NDTx-ifq52~8~8!7$-7#~&<tJ}rH)Ke>p3%ft}+I4J7RiYI|+fhFE
dL}!Ej%EHpPKGI5e_D%K*lfVu`|I5j-c>=tG`kI3~g~k_yx*-O<YLzrdne3l1jkFrDus<T8q|Vj9
GkZxRw1=hLc7cP4PKNQ}a<sO^WMiA4>lpMW<X2;1YkNvJ$Lz6w4i2^-w7DG$1QheX-`7d8i71LH@
>?PLL5)nqB&eT7`wAftoM397jmk7LY#6Hk$|SrJEsr?Z?1Py=^@_TML+hp|s8(N(d$OBK&sBuQ3L
o6<~CY{FUDc3k+pP7UyJRMW_*QfUFJ&1D8vKfG!*L{#=<tC0JFj_53v0d;_RS(F6=F60-x*hi7f+
0}rbkvT<@ZSD$7X~zRI0hNv@NiuUalNKX=$cJ@nW{T2vMGP8C+H}^h_!POjL6(hGC0E8@m5d23`L
z--O98I{T)^up?seF^u+2LwY)akW4hJR|&JNA2Uu$W@%NxMCY4vVRn&WqDYq?J&sBjr7cNJ05w`W
8_>!YIZX%29i@eG;oZ?XEpvWI164QUU)ST{{Y-~or6HFJ(5)eUKUBj=ugdp2W3fm23T5SA3a1eYS
O01*|{5mN(_Fj31=u!PhJo*|(Xt2|0+i}H)J^h}Dk+l_x>pHXsdGFWZe&K<y4I0Hi2VI5NAt8cC<
e7syBIcfnFUKFx=WV=&z?&9eu?~t(QaDcYk1)X={gqk8{4ZhoO@~J@RHcbEylyDf}H&Is1nv1QR&
uZ#2^tF>kBO(p1dSqd0>FH6Rc~hSmy`Jr`ZW(0oUjx$F0PbZ13SG)?nTto;^ta5?e=L&<Vkyp#T6
GbNUI`GnZq-1I9%?6A!==d<<oAEo0gq=q`<j!zz7-3NFB^FWx_dL7kZ%c|q}Mt6_o4aMg#OabXHK
Rn{%NBh@&Yd7%QoOZyddAVF-j$w!~`IXBnoM4z9ZeNFoY}0{w)b`q>aDzGcwW-o>N<*h)1zp%p|e
JuZ!AwVbs(rN2gM5pzwy-*KaYp+b1Nv)^K39-^s8gMuBSJSLOrp;uQnh{HnB^duXPf6=b`<dzFw0
J8r4o!#=%X&u6@Vw>+P13RaOA9EwYXTt(^=r%U4u;yIQ4#uo4lPZl%-$503{s>=O`7h*Y@Tp${IP
d3y~;25xwq5{e^gAZT&TGmWnbTUn-j}cY(2fq00zG%;gI4xYD3PSQVds$GRW&YIDpZfY!HMp~18Z
zsz^5#%~jsvqk3}7`!l)PTDGRdHNRjEb}c5;lap6%=BEQ>wFxs$_AWmj_l&Xv2+5vgg8WW3NAnd%
`nIZ7uLj?A+oVU2J3U|O@!oWqy{U!khKLmxxH$Nw1)yX|k|_SJFw<;8D@zejDvM>Pm%=oGP%O}Q5
Navt^~S^zPkhnC4Wmkq(x>|n1>lW`gHiQr*2B#c?E^|(aEj2?Ty$+erPo(R;=G|f)5^bv-uz{99A
9)-pnk*~(9st0&%l2Sx!M}XQj=544}u+_M<EghZ+VJ(eaSQo_Wln-27(Vl7&4&8TH-;l)N3VULmH
PU~Fc)GBr!w_hiJh-ZddIuXKFnFh-z>XGVtdVr=P3pU*Y6>G0g2qv7M3zylPMx)E=AqSan1|kq-)
vc0Ob^mjt^O)t<QA$Jf=^xaXa?z;@oykGY-@L!C_c@%IgfD<w&|>i#}Wkd3eHs2n+VFn0XLln*Fc
4WWzi(?HSRYV-1$zA*u$1<gQTioCneh0sQQ0$hv+_`FJ+uy@nOmwtG+puVp2u+SkA(pgN1eU^X7l
p76IJ_)Z=AFn#M^(`RmwG%>r_Rf9G|kt8|#9+@-5vlN6FFv#mThSdne$y+r%E^X$#r52NFsjz1i~
r^^XGWmzX@t{JpuM;--i^AVuY2QZdd$+z&+1Z|Sh3nb1+Inv>a7rM2`jP;4!I)I$R=<1GiqAVQ9W
`b|u&py07BiN$#1>IbHNXsc%=L&+TunpR{g1Jk%@L+olIHsxAAn0^pXmpYR2(WSI(qhw11(tttdi
L(s@h@bHhQ?a=`@J41%X)ndH^<>UFxR$XsDJ$MvfVp)cEapD4MiIJaQflZiD{~L@NJJZZ@%hM=ZB
Ny7bm!A)fRTCmLVp<!}bm?6UyaTp&)O5eAUL-TjY;5(LG39u$VmnDo6Lkn5F@&rwKjU4SM1pL}^D
!jTqkz;njd&_b)Jz4yGVJzwdVWm+i1grH+EWv#qcRtbfsA^RJK@a!f@bK^F}--eFeSQl$u%jY<Tx
Pl=`$LAxF!P8K)$9U&ECjtQTS#KCMXRo(&4pVN6!G^`^>=VdK)w4JKUiB*p+4hQ=eS~;N+eQi37d
||@21Yr%^TUCs!oa2ZE*mHzR3TcROvNB;>7?`m_P#P{*7&!GV>Y@<U9W-9Jl)SlW^V9jAi}I=%;e
i0mt)vK~yZxe$BeK$8^Ccao0mOv@;Wl4h-;e<gyX25+O<JK0R&x&VBMXOC6nN9jB`|vqD{%2Pke&
e50d}39BGq|_^d{=8$!Y>Lr`uh(l1vkIG-zL1k*8Klk?#H8e%G+f;y4@Ht?Y6LV2r}`zvz=>7zci
ZDA(TOZ}m{=;cjpkJT;?UH(Gsmd()r%V8$s8@0p>pP*uwXMkz|9^rL|qk1sWtu%E(4Edmu^8EA1c
h}GP$1j|SHRY+Iw_B8Rn-dc7t@4HN{Fp{+-)_L6JM1W$T6?1@UJsdI;v)dyz58d!*%h_eJAiJa@2
e>73jyj3t3e7{fOSFXP)RQ-|10fICe0cZ}=6rmNISyn$z$b!2S4~)Ujgytoig2PM1F<J&J+wM1P=
g~2X1sd4T+<Fzdb7+vsZ29eZNQaxWkeS>x<gfXZ(srct%B<brKSU?57pKpOgeRxMV`4~k5WBi$ie
;@xFW@hbUjptqqY$|_qzl3DZrC6l1H{XD`oUi?zr9iz8y@1tc9m^ho&<Bn3P2pHtTZ22GeK6>Hgt
1_hP2)8s%2y{c_J&+Jw{{v!2gDjmA3I<6@kq)kEFFnvFD!nr0&Aiv0@VD#Ss9_T>QT^qUd}3M{Gr
T!OqmWzyTNW0*$}Ma`vWt0<JBU8^xFbg3-i6e4m};EmlKq_zb%Rt;&3{qM>qQmM^q+lP>y!=>oBY
FKkPzyV#j(hlzo;fpMOD}^N?IV5zh6U<3!+tjk%tLCFxBnlu!bhxoG`KP8X4@wu36s!I>JN^tC!q
sorto?fz3q1`~02*Us#jZKGebI5aJdLR+o%<;ZgHehMxzfc&qe`T9>r#oR(*fR>ubTYUV9~l!Sg~
)sED&)(RMeB$MFq;@tK%y+B_knBua}cnN?9_noHYhPFss-r_;?p=gYfdpc~rm)5@wGojH|F;xWbq
Q-O;`YL0`lB)wX^0{@1_98KsZvJHWLwP{!oSpOo|1;Zp(tj@h-C`{l#;?_E@^uCg^d0}=fZGrXBn
s-C>HF=25zB2`%_;2?V9vthx#NhXFyH*lF;r&&fJkV~Pph_)I*+~`KcWZ)$&8T1xdhvNnz3m}0VN
sD16gZPB5mRX_0R-3ekg;)eT=JP>YEHi{%pT`q&J7|*$1V^}8mYv}5oW5K8$AfHz>g_~q$i*SHNa
&s{*DfO**LsnEO2kpjb0sCBoQHAQ>$(~8SWtQr^eMB47T8!;W>i?q;m5^@f^woC1PYJX0M{28o#I
)LYDXPzS~7fe!50GOJD2IT-lr4snZw^obfDsWJR|wj-i5<9hamhPsharlkZ<ttqiF`8uN44PbWz>
m0mT(@=SU;&Io+#zoB4Dq8B&l+&q(+MERr4w<~>1CCv={u7G3d*+g3o}EW3L0u9#s}Tn7)4fsX=(
Jlw@zw*e~sgUD9W*r|6|Q=^4yd*n}!yyBU|d{>2XtG>;HPZ$ZS8JV%A;XojB(PETz5)v$%>q)hN0
jvh9rzyp8uWQO~V$iT&o~FyZq~r}M1~heLUMtuf*}$paZxD#Y_D`Bp->AXnz_LoOuGWCZ<Cm>HRn
7Pqi>P|!D&Sn4(U%hwj_xyo&J-pBx$@j4(!pAc<IKZRJlBCQ#l^aek%H=o0Y=M00ZsU7)H*qgj)f
9JT_zMEFl9dl%L@u$UZLw1Y*xA)!Kir>@?Xe|aq6<H<v}nfF;LXWB$2~;5i9%pyLi<Je!#V&qZQR
T++5{2B-57f#3X`JMWHcfVV!bxywU06%Uv0(T(liD1v3mm<eF<a8rYbkl(%~-Y&`sa5*+M1H;+qJ
u=c7eUO)WfifLt%Rk>Yq@X`_mDrhZUsA2rrF6Nc;C}<Tc=8+oYnnQ^LWZTwaMvsqt%=6%~pctOgz
_*?iw85lr=<>=#bh{5ib>$UR{q8LuyJFGj@b(v$)gj)avM$=(i<^sludswMc(8`#NL6OUW0G_D@`
9@!i&>Gj&>fSnu0#&PCeXQ3oO$??h1o0Oso?o11yp5I!vI&Ev8%#BFxc`_FqdAEoZ9k<UCx8HpsD
3{!uT&m4Ev_#3d_#~73H_&zs6P#{!Fjlq{1p(D1*fqJ5HG!+8n#r4%>^BMxw!}nHq>Cn3CCyC_;v
MEoC~5+&#J%NbwfQC)Hud%V>QZc4IzKzgp+sJfX|$HwJ!L#)%UrJyk1dQeLsT;?6}Cvz-q`)uNQ{
qD_=xaviSRG+S?<1lA2nLt^;``=E7DX|9IBn0RL}e#Q$Y78lz13<6RNy?pt6@7u@yPN&0e3`JSbh
4Pi`TBu2NuCB&ytki~Dv=PwDmb~IwQ~|nL)H9%v|B}bPfmdPJz37NS4P&*i1_AHO9DJ?Wmy*FSHm
uTv3!Pfq*4CMVtu5tkFxq-S)E$z0*=JDX4_zElR&ZHo3D#k8dlsMGsxm<FRWjnqh162@!u9WPCgy
iV8w)CGM1*AqJfre-VS4RcEMf#`G7Bq~m*L{;;ghF>^PPw2?()z7@eSRkw&8d0>f&o<w8Vgc?PCR
(sx*U_vBfR}o$kBwy}C$+M<#TW0uH<%4h|8cDur|eWbAb^0$dF#n6Nl;*H5>_GW%Nj-Lm3tVjTt?
y3?G0I(In-<g&F2Z>4C<K6!}qny__&KBds2fuFZ494FlZx0JlhtcBW`Y&?4=K}OjoMZ4FK%RL^B^
QAh{fZ0sO@v=y2arabg1D+8aYGjy0K^Q#88k@N=^pLyj)z3JsywJy*jek-Z_rJtaOIf#FK?=nd@l
rH*0-XPKQdUX+rh^o!W3YKS*lN~6su(v;(cye8tQ(edt~hp0cpgf_o)9@6!=Or6CMYmE`*vpeZQ_
~)5sH&NP|Jl1_o{4#+!mqWVy1etgU;3BX*&I4S2CIHECDox)aIqi7C#CEb!1#H!!_(E>;B?Q?a6s
M=0q;>3gsq5d9-Oo-muP*YVl`AtT}n)!$0L_-U(h2SIQXT#DdAM&`UPX)O;n3z?CKsE#8T-jv69v
>Tbjnbr0a#XN~+|-MwJwwJ$&4;R)?j>?F}wz7~FMO$$=N5*H}a!srTST!a#XqfSMYlRw(K&EmyMy
B6#0KqiKOV=}KZHqs|=;7)efpx6HB)5=VMf^1-0X0}5L?;T=d`}q(9B3*E66s?E)h8?pH|4X^}er
>r*oL>%9r?dRXI=S-OZ?>~23xk-si9!q7uT-WTc&DRR0i>NWb`mQx!IzQQWvrl61F}9`7YoY^Z?`
>;?kt(F?n7#Bc^fsa)biF|CW^#;5t(R#-O6xv4kBsa7))*(6?7A?w_TXfXiYPIC^bz<hm5634SkV
hy)9m}Y~u>DXr%lMtzZQbEQq{GLQ$Dee}SsSu8uN8T7J64K;AsVtQEb^LB~Na+8j6_{v>_<ZuU7w
ZIGxsoGFZzFtqV&A%?9ua*|>pzsp)WXhTI6b+?E)B>#f5o*UwP24q7KRAFZ*I*Ua95eDhifBhVcZ
(`DjX~#kxx3aBMMe2)G3XLV<kjV2_ZcMB(iC%)F8?C0%6+~NrdE>LOL`9+jK%*w+P~uA*P~ihGMJ
Oy5Ih|Y4imZ4?Zg3+iXhk@p2HcaDis&4F8%*!WyS^3y*>jHx3oukZ@|+ROIG3uoh$Bt!uHfjygq%
Q<xQIkE=>X#QWE!2D<bIM~!y&Ep6H=Qd%k_K*PIFQ+j+0IJ)#RV7cy?CZlD_qq;KTRtAG&DT3O+6
;*9j`x#F&m$Of}z_f009RsP9=@K~>rMg?`0+2&YA2?PM1&?<u;Fa4!SdZmiUvPnU&0&s$0ifq@pZ
(@Cd|h;MT*w0kL9irD23%xwUIM1@uba(JO~ZBOy*Z}yo;v-rIpD@Ea?D&boO9aM}qM?+*W@BXRBx
%dk9MQIa@0nVFv%o6<=E>&#3MdDCGK$>KF)$#4>wZzqt8dM!XQ%|Vp>UM#T<PgX^$C%LjYv~D%tV
#f@5F=>Ra|>aumf39%A&><nN88_2Ms|8iPJAl)lzP^?_?^!@6?&8#xY&mHd?f+y`ii1k@#f|D#@s
{I{FI~we)01MNmSWUjlJi9c*@9ekyugizH>v}QG7c~Y~a9lPC`q@G8ixB#tPYXakzKkn=GxaKnR(
SzPRrgVbpEYAMpFnPXLcRyFFOlvDUilaN}YE!9)-l4LX+zsOA{!)a)LeDUjjy-k#|28jWe4I<24=
34pryz2kn(bTYm($tt<ZTG`dF?&Vghhq60(ubwt^iAT$F32g<ZXh=z)qsBfPMsC8+QwORPUma6~S
@dUcz^!oKzt=TmYvuM-T$hQk_~lr;SHoHz2Dqr>>aq5yv5r~11Wgqim*uP!V?x?i9z*nuZ#+A;ZP
AyKKbMx-W*F-?k{u5dk7D1(;>ee(wQ2xNxj@2@LS$K4uoe)lh>!!3xSTXk<N`Pz#uspqD&FN^!bH
{&!S$ftbZBhBg0Am?!d2_=oLV^EW?}#P8Pe)Wsrgc}yEJ~Vd>4qJhTSMHWFyT_*M)ewiC0C*mUW@
6<iVd^z7y6e)ylPs6&;2<vV-a9c1asauPJi8jPoyyWYKO1=?ugCiSOVdEuFM9m<dMg9yn$L2f>3K
mE;&@3w_zIkkTqa6P9xk!*;=Vx?ctF-h8j!VKCew-c|?8%!q5i^&j&Uc1#_TUB>(GpY6ue`Ar;rI
DPrD<0jvkXV=2mFRm|R?0AA-ZYb!h%Tph=FM+B-YsWYcxduq5C7B2>@;eG(7?kPERe|xbP&3QMdy
NU62h?NmO|Wl=#kn(TCwC~)qH-R#;}~E^yGJySA-3?1^f3tWo0$LeqYK+sjck^}GQQ?`1wMN<Ioy
#dYBPA!J7Iau`2n@zw}}a2|Jx0G)p7kg<HdNdADYS$c>%nXe<o5o8OgBA<oWsi;kN+)^YaD9vN*r
*#T3)R?RQsZ1r<(zctJ8(br7e|@E^W$*1Q!Qwt|CJ(B+@1Qr&L&#qkF-6GgV!4h#?TR`Bh*+9z*b
h$x8LxiKkAqp&FwCTC(1A;`t;@;crYw|}%Z(O#c0o%YhR@884kO2$S9ziWO6*jZ%W4ZDNE{srUKu
#caywEohv3fb0<#s@=I><O&a4?n;U{Gw&!73%AyQa_dD+`|(0{lh;CVj0%1<+KphL7rY+Z42{fia
@cwY#a779EU`t00}X+M?ub2V;Dw;5x<f2FxjC?(WXcjX8d9Q5n%FuD;Ux+P)+L?1)L(S{yV;M>OA
H;JZ86&)OnR;*Of}JYxbbhA?+XhF%?0;gSos*7H5=Y(W&+=SL;>A#?_t+PNsP_pnPI>)q_4)?R%@
fyU9yZairq`0?w}ac#kL8_0~K?*uEw6L=O2iWq*vz1dddvna4bUeSb5YQ4(hT4&_s);^8^~zt8Uo
RyYi&*0)@X?rU+2Srui}&j2%@qp4?MS3KNb2jh3sIExq0^Ncd;Qb5`PQz?s-hkJX6>!3{;8f3-;I
FaL`$j2$Udeh14T$~Utvb`+ol=cR=hxZ4;{_l!mnkZA}J|0_WFRSuFrkr9*&Pwz_yn<C3kuBgMdi
F_O_r34@Wo1}{Yatzmc#qHu$W*)V+bBt{9U|cpyTK({Kd=!zwnVa(GJ}6YM<APrQ-^F24xMm!QBC
fq#5!m~y<ZFSWJS}zMDnCu-**6R;Xa65CVkIZN!qkjnFS5jhV?Ersh-sCofXt~c}$iNOfcWAb@0O
v)P)6gY+pcu>n%eQ>6Y|8yyk00rQ|lez9f37ea%hQRt7t1K0alrZ=%}(6NaDHD<z3<tZxJAsAETK
*Y2CGAgtk0#E7(<B^Y;2qqJ*Sfcy~Zj~?&&obi-zXAd{WVMQ5&<Iv7``xgyssUaBE*sIgiZxr_Id
g~t6SeiP{x19YN=`)kT)X;FZ)-YGn3kpvx*5a>VmHsN3hwXBlY<KbE`ql~5y)o^b8LpcEPi5AzGw
HBT5t;gM{2i5{gcSIg;WKCov3$P6780b(CQ(UW&slh{n%R_8Po;A~*>`b`Ve9^fojQ(8*EXhx%W1
0dbYNRnNh%j@_KS8*OWcf{I$^`O&?aT=pmg81NtHiu#m1z2+!w4`$qkNpLfiGZZBD=S3Gb`~8ai_
ZWy;vtI?z6U0z*A^ywU+q3h-}ngi;Ts+t?<<p_7lpNy8z^Le>qWm9!k2hD`Z7=)73XlcSWvv#OhV
4G>Qjk4^2W^d6g`UC;cnscj4ty9Jol;5lOm8AE*$XjBApd#vdq8J9W5@?CgxhHTD<h@?zQ;%I;%n
GOx6Q&ebq#2P9qH$pYrnFRB*+~y@W2Z%0K0o$*hz>(O&gDdO{#=a1XSGAQBN>Gc(?fE$!07w!$os
R6fb2#9XDk(1PmQ0x)Wnn1_tnsH}iUBr&JjZh}CP3RW?B^fLyiDrp<Kdu-SNxJ3hR`VCHlda61TQ
cqItFWx$?>OzQOaDgMc_xM*jhMPQO?mBxZ?7!!YgwoIr>KK0!{$=n%A#C5;|&xIefCjKa#&+pYME
K<p4h=E31VpU(CiJ>sEuQ3sPWVvHixG_{<_Hp7~@FLea?gn!(};d2Z*$dzI&(5Uym{<z}TDIOah%
<W$>LR#~SDd{BtpcE~B$P!y;ehtiM~^AF+_9^9BqKv}Eq*bp@P!HLnWhT;hs!6h2TSTlW6FW!hBl
cc-(V0p{vtD9OzHufQGY!i)h9@g`%HI{et$0-9K<+CH{<H)U{-o_T|^hL46*W3R$-!<APV8u@+V^
w>_>eqw+%_eOXPZh_clTj^;B2Q}@{Y}<SQT&{WhKh|yRV{ETj`fI1k_b^dZz0hgG`3JnZaW<G`WJ
&{xS7ouR5G4=>~i+&guxk!diato*;KGa-eC^_DmyB*r);{&Y<c@BWgk}?zHs+91!G~hoxJ$gZC;!
a(2EDkFHpsXY>3+#MGe!FsK01VcVwj%qH_U1St)mDE8_Q>1^$xgo6AfQ`?IdJ!yZ8iydT9N?p%O^
c8>B-l!`lAmloBos)yLv0NpZUBUwJ8AvCq5hF@<<U96FFgB@NzPN!(mYCVG9MslQRhgm$d&_>ifn
dzxc1#G<lE(1tCQ9<Xqq{BO6KqHVZKaNy@5lXZ`Z<U!X_iq#t>+sB|j4Pp;YX^+qJI}#Ubz)S5IJ
bC^m{$!E*c%bGPK~~zSf6B0Aa;5n@uF!;?4D4UIeL(3`%@14!$z}qV;)N`C4zwLVaMY!ky7wm)T*
|mdLq%3Ilx6aM($0lnaO<?n*Gk0kg=FhsMYHDRzS`Td4TQ)tD|W=yPU-0tshV<24x7zA*J>&gs13
54WXac$I5PYyp(nK-*5Bg1etDo=Q*{dIn^S<$niRQdSt!!G+K!;pd#qX6}d2uxY>NnqwEpaC4K#H
Rdd92ngHlt7*)a#+a{{6*$z{Udhl$rgm~b_I@UhF>>eC#JMb?xR<)FWw!vy`uF6O8s1njn8&tF`;
}oxTYSkb0cugqYxE{fGP>H;g7S#qRnX=dbw<Lh7*!ZC15H_o}HHoX%rtf$cmgXfc1<G(ya<HgKQc
Y2$>R_wJ!15$1uZMP0)nT~5{qBz<T?_Tpz$a~7Bx)#HQ+cRue^INft$+PBFsPpod~3Kk)rm~HY9z
Yt0u7p(O1h{<V&M%Q;++QC5RC+O{G}O!bRoQ^tt-2^F93{p`I<+zMMGb-lz(7-HjwT$S5Rv@RKYv
A<7z|?`5tZG+zly_u`LOV20{i}i-lxw6`9Q?Ong<J{uMa{OD=9?2Z&#-dZcjTtQbxdpj{J|YeLST
T5ZmdCp6kb7RshkQ7~H;rOKtKyzeO2U4?vEW^ojv&0w2jFjrT^Sg-wJwB52gbeWfJSjP2d?|MPhY
MqW@tMl4n!uI2j6-V|QAeGOa=hJ-g0rjQ>+o~LRUEo349CUn>=LME%Ra?}--EYvY3t&Gj)A=-BNh
)NDDO4!WY<P<P<4HV|);rbaFljLLgF2NG;n$V}%?#!eWs(5xN@MgNpUva+Iupf6yr`}+@v$Ob{Ko
dXY^7f@@~s*4|6V(Z>+G?L>4FL%8lhZyng~T42RL4NPGJtuXsI->mkGyDdi@TMva@%>qgJC!+{6=
(_KRMCbC#(eYeQw4s}iW^vO_Cx>dc8mS)e~6D<kz>A0fxL(RIX6j-|{uQp(}~j#FxriLmr2y7rWU
>10h{Vzm)~0#<>&^;K9Mlm}TK21tlXuqz5sDtQ&E?QvIZk$jh9`T_KlKD$X5u+s~bMHz2Wt&5_(V
tj3d_^5@K2#iz_S)Xe(1nb+Tr$(&xvF6;_U)dG~Q&JjP&0>>JtF9f9Eo3F<n|@2g#_qbNM<O}z$a
efScdP6tqdNALz$M2rwl%M}phQs^2u3v)8L2zifrIAW3Pv8p;+AyiE6f5TyOd6v3gJe;B7VumTg8
mm>kQ98=`=t^`=3=g8GmW*msX>L-tv+`c+81L?0VXD$={E5|I&5j%w><t7JIfez=H`N`E&C}Z!x!
d%Yxlo8r4NuxZwu=e1|TF*Sw#V)3xul|B1KE?;dHn?jm5Nsw*1V1iw1awR-Ud46&4iL>wqwf_)`k
H)DHmd^RMFtx)4tTRUhg=WLEp>T|}n|0!>F5&_j92((S*=PLde-llXOJ}9*1Jcn*TB^tC8Rb?#W=
-zY|>ORmjgw0g}96E%EEKe&~&PN#d;OKmZECbXOj?{-}W3w>9uxTxHE2hV-u0#}Mj?{;SVK99j3W
Bq%33U&k<mDF#Zm3R+<W{GuYW)7{Mmt+a<_393Ja3O``&t%OoMup&v&_g!&5OYl1%X?#J*ArNtBl
6lzw4UyRoqMDAA*gMHNh>~aH&L!WOCoO!!SbC%_-yU(_UhibMTW!A<}<&Hf@*#ON-k~V4w$&q@zV
VAq$e6(D#d`(jc@(P0GloD-TCGjNy39y}(w{dDh%dir&*|b)7OpA`PKRoUS#kYL&=F*3FEeoE*Gn
jg+sqFQ0$1f3Ydt{x$(!qp6{rmS&lCjaoyNp*9NC8Y)fZ=37s>3{X0a!CIw~Ka9VI)dt0qQ5bIv{
PmWWjTT|H1*S|)f|{<c{8udKwu@>lY(<LH&b$5-w;ub?>$=N6oJG=bRcame=9sUyVEoo3vyNIC?P
v|qLPJ?(4XsCHc3*kM9tcQLn)*Q>BGV6i`&adYjx$zA>D6D}kwzuQb^5m^Gub(_<j%S{2-j*futg
|UYtqAwHF4Utn)q;2O##Nh2cM=o3RnXl02^zu%O(%=#m^rev7*Mbpx!GN|9z#kfx^8;vr$X3GflC
bx_>agd(3mxB{*+$pWLqb8UE_ee68;#9|VuOU7ChZXfcPrq!8s?j}M$SDu$CyVJjsunTnz2;-xYO
O-Q+*KD#lg_;#Nnu+%K~_*C}W16(-Gh;7F}jmt!lS`(O&sh5fW_OZwfi)s!SC1(I)`g5QAPZVseG
g;2&q3)q2rCQ_*k(Ea#Q$o$AM?KJKUbX66U%H0&dg<7QmHL4WAzHbrb>dG}>p-t!>_H+fWwzy$h?
4eA=mAP4$~X$cfXlwGu!%5E7L!}tLd(b+ngAA&v49cX`=D+RM8lda=hGAwK-w-L2<hG;oly2E3Kf
e(XTu{YBh63a%Y@wGj)I}+!`y&w%4((>noX-ZA}cwGG-i!-Hg_`Xns#-^y5XVK=mm#-L)~%IFzwg
x1Pww<T^|wL&-5$S#EWh|s&nhG6tg*N71e;Epbew8z^~+|M);?ki-Fd3pvi`+7ByLPs5niT?qN9S
buSuCbJ&2arV*_RaYFm_0D`AMue+vMiZ{(Ba<d!{Q?-*!3vFm2a&59i(?jV4lpU3%rO*~sNA5rdT
UqQGiPv%b>Rh5ze(_0V=~Wg21=@$hKrm+m2Z%%K>_vLbadb+{@*2c83P656%`f9=0bDlY@@PbFMk
71GZCapzN}Qod9=>hCLXWFi2}?ZN$ZO;x@Q0ywf;x0L2nzv@j?z8$UV^71(u9mgjQFDwx*p+xq`z
WSpnO(_<dTF-vD4a_e!lO_S33iC9^S#&dnW2gnrE$GPVxr_iJqpHGmKLB>FXkZnv>2LsWjbATvE6
oWyXPJIFSazozpfSquh&e%*hY1(D4jA@;Xar<ZvoWq9U|duIQMM@-X<%^jSb*TQF*?vh~V>UY{dE
@ud~}XT$a_k|eO^1Cx!=x;bUt!g&UmRo+}Jr!-HD^2$yTlO_3Pm>EC3PqH+|x#D?vy_~`<VR&?h2
W?}BTfn?zaT`zR84$}dmWUAOc22{-Bd-L4%d@nUBuOx9C{xI7ak)TJlydH9gf6BXhO(|(_#K_cu-
6Lcw@9yH`GJ0CCHjf8i5v&Mn2C)5hBHH0Q6FX$;xc}oy?lTC`ebx=`d^p{dawWZ;P5<qefnnf`uM
~19|B5{{N~5kqvt;yzdysTj}G|3yZ5KBkKg|?dUf*V`wu_htH=D}?Bw~|H!s{*{rzvxGx+-9_}MG
y?D*x$hhO0F!Tx#n!;ddtLT5ieJN<wqd(iy5_a`6TpPb;+vtM36d;5x-=$aSQj8uT~ua8gP)SmbH
)FTX__W1bK>Gy9=UO3Mm)5^Sh`}{vY{PON(bo%BeDD{HPD9z)aPToH|{&4y_AjZ->mlhdZ=JAhjp
1*w!gFZW>ceG#My*)eqaQgPm=<L;7>N(u&a&Uq@^v^zk|IsZRzCVKJ2k`w{_})V=_x`u&8+r2chx
f-L8Fpv~Jm}F+pMLh}XP<r^(a!<>Jf<IV&95G3-?s3l*OmW!@_%3c-;@9M<^M<W{{jAQ1wa^GF4O
5`G|!6^_t6OXm{3tZ<uZ#wroO=mS-!F+)Jc!$>QMaT7Ox2LEOE{%dhw*@4NX?3#t2vI^rZOSK|^_
Z|L|eZcRTW^Y*mfk<BDJNFr`Rb^bwo8z?eO~;K>uNQVDPm>{p`Qh8_HPc6^3g(hp89JD$cx5xn}$
vB<&`GWmx>#@Dnc?2;IM!3jO_`s`VoBfp6=7-jQaM|XfM@kw!&W{Hz1(*%+kjnXVFN23s3OWmlHY
|$~j>ZI9xsS@{8Ucpq|m7}LHA^^qJRkHBEEJhTV#Ik$Fp`Zy3g&3f*RQ#)TZ=6WpjH{N}ifpmf+o
7s=QMDG8=IYud70}c+A*Q4R3Ct%!U-J}WCZPYG9E5CFa+e36lSQt=+OlOMEJ(*ck9Kt)Xi?j*1=d
S}chE>f90;C%ydolfN1iotr=^$@8`>0!jJ>t1;J)lC7@8%qLz?y0zSfTEw2uy>;GfXoIs^%;kNz2
uaT`_-_h@$?z%LhhqR5Rq)QDued`_8(Cs_eJs^EKu1?{<W&a6rsPq^H`gF_Y=BfFP*l6-3F1Nmx-
6ywoSn5C*bsRHTgQvnV)?=CH61!(BqvqQ~@Fg9eLIo8^;JP|N#3HbIA7q24S+HuL^s5z;3w+iD3t
kt)&5H#uPJAvM94fSteQpIW}qq%7siOurZU9Qk_<)*_&hZ)*UhX>#$AIH*9v3LfbYIggRdpw#9wy
QQOX5xgHXuRn&^n*5@K5e>+ryl$YF)xup(9GZ%ffEpp7<h*#&0^`l!^G1EhY$VKFy?RAwcKrYJwv
0-53qr$_lQoUrGEklJxYkm0FVA9GjZ26z3>i&hTE``4Hr!|dfs$k8bhdiQO8ku>R@Sn=RXZ?g5Xe
K!#w=J^By#w^ECXXO~~2fne7XyB(OyliJ-duTxKz3CQ8V~E_a7aWVIT<IN}1;cT6J{6>)dxY+j;C
hYqr>=1Ck_4P?yspa<EAbIOmzv=f*r!eEl|I^3LzO+KZNSuEtzRc!zw=oGLial-}D?YzvyOv`#FG
cnUL@3;^3a%$ThDwrAoTTFJ9@uK&m8Af9iYEtP4_ockH%EB??sNKmB6-s8ynZx7r6wnCIlPw1~g)
U5UkNnoiJXykj%3{nNeX+yqG>NZJ0LVR-^TPe8*?Nb8Wu974Xd)+0Aa~#G@5oGBbr>}oJRw!VkyC
`9Rm0sUO|8z9>ctZ(@5)s<u@a5*ae|gsd|K_5gLYb0E7h6ES%+(PBn*Jv9FZb;dznwwhNeTIf^3+
Vk6$vEQGIPUN&Nm3X5c({UVUX@IBkI5qm7uY(Yh5l%8ma+5MANw(Vs<DvttO#2Yz(Mz<Dl4Be2@_
W1==&XkCuzwFmU(fhrfvm6pqC%QSW^WfelM={J_p+6qSzLDpJn#E1o3PiwoWSpmQ7U9_Pn4rKe{i
pE%zZLVTNq}kF!(8q4S8GN|u1<}IZBS0TSD-zdwYv9*F_`Vdw)-S;pM0oA_(M*P=-x?{d@h0$eb(
xHafvNE+KHjDpID~j?;&P(82QUVc#=PHM+RsyV`C-0dIIwt=3x6>D3j2H+PXf(C6aP`=o1Fox14e
P7FNoDz4AyF!TB7J4A&qHCShf+<&#KT2(+7lla%5M*ul?R8y~z@!xw+htaOHrLVMHGJ6{dpPx2lI
7y_cRP)+HS?)?mDaov4G=MjF}&Jjy(}GrCY&`_l7VLMYZ>Xx7sKdR1`I%AkeT`z-o_vr*}xWVWXZ
ks9(cY{~NnBq0eS=FtsO2|X_VYYZWVOH{o8sA(-rj1Z5vRJ>SSZvnFKOqzxa=ii9ohgjj>2Mld2Y
y)NzQQWI)<A5??)bt}Il!f&xlU7i>Eve!K!mQGcx$4<P6+DPnhak|@?pGr3s*gO4)o+7{F{<9oR2
z(^>2*dBRE@znYWFsdh6>Zyjg<bAZslR?-?xI>%8tKRG#^Vun>IO88zoPn`<049S$K#SHaNV;Q{c
8n#P4z5YPkQ7m%r(FmXtU7#F_!!9FEl3X!M`|+eUxOKEO1CcJSHh74J-{s-9aqSs!nq7Q<F$Rmh*
RrS2(#qC2{FJYVh&v)J!OKJ}<zKb=1WZB1lVnl1kUr|S6+I`2UxRcfoOI#oM})EgL=gWN^g`UGB`
@325p-6O6@eoqm;7DZXr7~kW?1c0bA($BRiJBmj&&$><9XNpGj*mFv+d{8v;mDh-<t0t!DUNx!rr
N-%Mgjc$m<G~$nH@HVQxPJG)dvxD!H@aQ}=sx%V(8@W=YA=oGNB<H?+(uhDuB;!MXJ{L`G}J@%YQ
%&H0g(vMnyDjxr>2!dPu-tY)Oa=-8K~@)6i}aREn4hV%e|oMHk<gc*YkvkWyj{ne}3~!Tp&q%M<G
GUP(y4yR6JL*P~ix6<X{VfK!(7LA*4sa=|b3m1%r*nn2nDKfHB!<iE#>s0L7sR`w(ZAyDXOY!RD+
Btpxyr{yNX{?_pqH(}l6H(Pun@B1t}Ze2U3PiWop1Ke;{M$K#R`gt4ItT4h$%mNllgp2EoG6>XMs
*Irq_g4#-sB%z@#T&N+Clw|a&B;00WT*FDb8L~03sR~a|A;q1y==)*{G~T-D5jt8Zm*uZA@YQl|5
j$?wWTZIsum(gP8YKX>jC^)&CL2rDw7$t9-nBSzG4<V9n2Svw#uGCne<Z0YS3mII;M53ez1T;0(9
X@yzcpV>`C30{@ICpsWm&&y5T>NhIKWG&j}4Vv`KGE&B{ELZnKWsZq3$GaZK!`!IfLzoZD*G~u^R
UIhuOV0wo)A{;oGRpC%LL+$(FlzqwSht>bsb<+I#9<P&MzG5V&Ujuj*o-E%!MlTL{CjE=2yVuE?#
eETfFNZfiiWx&T^1x4r0Jg2jiM$D?U8qw!$_7O#=RYmHUWWzCXctm2w=T`Q;?;%#t>Tf5ZK?52=Q
aOiz9eAHpIg_oNx!jhQs>0<k}^-)aKmS1$)>e?E`86{Qw^=^JU6cXN)IK!Ei9v%FVnv{dc)-P0*A
?t%?X;^5PYdc_g0WqT-;~Sx%Fvu43hTZ#<!;5uC%vy!e`bb$d;K|Nmz<c#6o0h^BJL}5gs3|1Zm(
a;gwD8MdpnJxhVj1>r32>?=hBm#8h+6H$$5MDJcx@4DMjM)qDnj3>P!-a8{b=LP>QdCVvcnl;IR)
ABYS^U|YJf0gw7JFJ?)lr<9~^#JJAHpUhZsj~i-tA?fAj8M$zl#TX~i^lu4F(s8KJ)G$a^?>83|q
Isl|6R-MgFiO<9i_li^?5N4io2D_A{1of?~1pTFkNv`_Em(Hj2Dlz+N*Z<04k!se|TG$4x7t|!V)
gHOz%veC&M+09{<^`z9VR*PE@8T&?MvoE=`s2j>Q-`jhk2@UGmud7myZwyQ4wD7mU<IS-F`gUtaz
WRfWtWE7~qVwpFFg7v}xo^f~w&;_D`2_GbA}s=Hc`YTY!Dx3qmRjSEwuCygsJ&{M7-2%MDP`Somg
wnI`v%AdOscf`faDSByE{2hn(HtdAdUC7IeizsR_%(fs~+|Kg`?|lHM;(q(e?l8(G{BlVi*?^y@+
TleZZFn#?NPnuP!zW4@EV{cZ6$!sNHWeu5L1ap<&@jj1u9`$xv>?!QNo2NKZT`3_224L?>>j9qdJ
PI~sk-1f7Q0ZE_KozNm3RNgmx60>YZ1@D#tOZ^MplwcD!K@7-;R<F=W7(LR~2BX;T>aE?=#Za%eD
rC%!QQA@~MvtN@aQ_&l;fpOISCKxvJXoHffs*thAy~P14AbMKsW%J?bYk<G~kpq;WB&}U0D-2M~R
}&i#&5wH8Qoa2JFq6rA{Gv79dIq8^-!y|_F%FI#b$q)?&*hByNsw+s^pHXOxVaqj(;qkR(H>qF5%
oe(U<k9h*seZd_-5AC2GjPXKW@S38sKlBJPez3OW6DwxO@RjwueW$0Tx^E2@ED0UEA4i|Gxm-I;&
qxuG)_J`lL6v=0=HsjT+%EQJe8y>$ZoFZ$j&3_liPW6<()DRmeai+YPGP><zaZ7VNq{m^I@6A5;F
=x|}DCs80;RQP5rwE4<^yf=|6VnlI5?$q|LFVzERrZ#<it^g&qL6Y#Ny0`1!68!)45@B3=QWt#|f
mfD650VU@tJiu>I-1^DSW?gMVbAJnZkJh$ld8+#A)`opGuisWyN>C0)4L|=dT_v{`oGRDC?$xZiG
^el|91N%M#oIBr^25PZVUg#n`2dE$3)L?C34IbwIFGGj3?5Gr|DGH#7i<;aT=v!oiMi|cOw|+MkI
thB%vVO%<mw0w%4{bMhtIlH5*T5c;Cz2_xMqjS9M_*k>$P$5Wq}8=M*&X1)f@&B%E2Dl+VECTkaT
IMtMg2xEu(yLq&s_};l9=%2K}W}mA0BJ8uQDur-+E8XHZXegXX2HAfcKPorcp+najNQzjTVUj{6N
BOnQMHH5n*KSO9BlY-O<KRQBy8w+bFyGY)Xa^K3z>%7ozEP>g8?%BW^HAl0(zZ8*p-YSl(E$;@Nv
s;qfxZ;jzmo8Ecq+NKxH)XO46^_}25TaJ!42y5#-4(w)a$Ahg}t$Hdn*kXA!FLh3WO46ZF=5oF{=
dss%iv!#kqcXO1DncET%FN-Yd*AEAzsQNV!e)0>)5KyBgcZ9+@+66Zd7LgNv6DCx+m?1J`_-b7rn
NTLESExhf@NNEDEj3rBnnRVkS*$zLdsF`NZHYmsUQ>=qrvc!a#h%~r5jP^phJrH*5W=QJLaV^CyP
wfA3blk?~0Ay?vWZs$FT`@YP*qj)~{U1ZbFWeN_G7Xt>r`8Zc9h-w;*&?297~cZ3QgvAeEyn4(1r
EnZl0UnLNrecm-+4nW+KLu6L7d9BCPw+GdhclHYPHxJ7zB;?Sj5M7a0qb)fUNyQ#9_Sj^epG@j<c
^OK<XluVN{=e(IO-v#kv#zElTFEgEg@7Xk=G+5!Uzh276b{nluuNRbMx80tv%A1_x@9E*dQ;aeA>
#tFVL&{-L91PHBV#VP=a*Rf#Mgt5V(2JnBN#_z=t@myF5|eX5&*{9|`}NoJ3_b{>h6VN>s{({szy
8W5`R#eKz&MLEpWt1NDVxaj71Qp{O9{y{JI^RzD5kW87BtYX6;4w+i;<gN1t<Kf&4KSuVUFKn(7{
=<xRyLpDTT1UPV!k&q9yPZ+R>&&rYMsrj+&CGX7m{2s^SibvlT@{#W+o$I077JBf>~`9RfE#4LVn
s_w*KF^)(wrcRtPv3LVOkK55-lQgDivNP!dM;2%qn^D&ZM@H*v8PIHQ64+xiVl)$^2xWvRrCM6Ot
1#G`OVZ<M!6f=;ls6|5Q@;Hzy#|5Np8nmkMrzGQMDMglw`ucSNYey;kIF2g@R**ETi1tY)0q}^p1
9O8nXjCXw2@+|7KNcnkyT-=LW*ls{xj(Zb+HFKb6zz%<Dvxi{<VtS@2Dxn&J#4pu!#Ll8UxZCk-~
wOZ3PNMo$%MXUc^j5VeT3EFk9bPIIevX|VaM-FXB57Wg6*m=AZ*^~FBs53J{GIOs&YABoo57JERX
T{i$Grel#I)qWKE7!#d`(ACN2Ru3l6(TyKR|a5F-#Sy8MyzHX!aMLD=nd_qzLs!Hn$SG3(7&7-cg
KdY!|)0F%OBFUgReR{uaX0Si6lfWi2UvaP^^pxa9qmhOk+S8qo@zB&DHHhOpRe)Jlh-0%{u3%vyo
gS`&)$RqzddE;CXX#nz{FBm~vxDgdCqD@b+^MfBT(BzdQ?7}o#WDt)#4SIcX^78Hb*P~}|-<(j~J
$0%RISJ;;^foOx;RHV^=4qDH9`x)dS%NwM^PQ7AwA_}b!FU?qrsJv8*fdzqfieLexldvAN$nx-ty
;SaZ@UX`y9-~t3xB&)B#+lO?g+;5^r|}0y!4EzR(DaWyD)XFlN}RYXj4G=LOv<0qJtlY>O%*^L}O
ydb{nHi?*_fW1)l8ufc%=JBuhprt+&p-{hJjT`+P@J0v;ahU!4Srwz>U{qPz~c)O9lPgg=KGm-ko
(#U-rrk^50!RlYE6QQ~mZbPRtj`d)g-5$$j)P9QSQSVlmha&AbeJBhAL5R!?u2s$)3{)qG9Pc$d~
$b+k@5E*VmY<AcmTwFL^Q~ZI7V8G8Qh^C`b<#8WzS410iXxmC(0>z8E>#fs4Z+!<0`i2hZ<rj5O6
GE%Sl%qd&VUQY*JIpCtSjj(B<l`Z%$b|~$tjd_06qa^WjFZfS-UM>r$>&AqZpN40n8G4otk4GwQ{
fbt8IP?(mBg+$7lq0n;ZY%JVK^Z;>9>m`#7I}nIi?DdA~C=G2&V}$y0PZlP+`LS3`qG4JfUf<KKX
_clw(qq%{jIOjB4A`34*gmF1j;KFM+P5Nzp-xLFO?{vrk8yk`4X1LY09=V!sdU5Ha|q!;?YP*idJ
JH0fHfvMM5jh$j<{kA7if9xlNO2(m-An|9rOouY*=vvXZVh4^f(4>3blI~}@}KyX6ecEODeBP=N;
-hJ8O^&02XX+q(W)$ltA($MP8lBo$6D)B<Sh%6tKGRQ})$0){J5~wDYZq(9vz_|&I9d#=Mc>4bJ@
rNJZpVT(H48^MD43TrHF_Y2$)BiNHT&Ou~UY9vglQzxWW+$}2<aFY^t!d^m%cMIn=_Kk}1lnHB8S
@(RIc%5p9w`_pAlz1PP(r)R)Yk7~H<|sHB#y9?X;2ag+W%ZkD<YOzb(5N817_?T@LivbLnq=1FTj
zT=s<F~MV!0cQfgd&tQM`NBoqj<NT#xo!BQ8}9D%=<3$eayDZE_s3PTfc9?YllIDsA>;=G_}k<2S
e0V*qvt=6Mi0T^|nIG$XK`d4i+K0H7NR!kURmWE}koA@>fl;~^APAa7Ub`WvKg>|c<bGiv8Q9VOa
SjeHIhc?1qqKLq^8D*%?4MlKNHi0)FzW@jj&=~#^gY_apQ<EUp=A#=J)(8W~bM_8S4vmU~LWE(=G
@x3u5>lfi9^WVAg}l;!wlOy#ye2IB-6AhZ<uU8j&UMTL!XpXsl*P#%@t!fc9DhL=!9?%k#l(81b^
>q?NDqcKQS}hnDtM}Al^ib&QrT6Q7?ONxH#N?KXr$V&PtJY-4$Q_Vo-|Ow2XKf#aC3D4?rf8k*3K
44C<?1v7CIpZE)vfepQmGVtW^m)aLhb8Nm>g855Jofb%KXn$RHwiHsXgN|7j67VQC$S1kkHGqhnH
gO41HBh^LORu0jxoCTwjyvPU4_hA|!8fB-K}&Q4yPJpbSjAkWIwMk2IKuaY#5JE(H)V>1u8X>vEB
eCe8Pz@gmY=Ho7g-HXNv&=OfK8@$@84~>n$bxrCW^7D=)UnRlDeonKjz0~WAWz70I)WGI=6o)zDG
+Pz!+19k8CJeLAvPz}k!_Y}U`<>AXB8&JL3zHs2$1XUfmadQ@wLfzUE1(E=MSNKV?R$Rv8Qyk+v)
s@wBxTS#w-?^Gf)$2#2-;7B@G}K&SVa_~0JvZf*wMu>xAa4N<6Y+Y1ZgFySEhNca*o^Vh>c6Y@h#
H(5y)m!T&Jd2om0&Hl$I+U_+`d4%&uTqxEZGn0c;6zCnxuSF&&tL`EqZ6S@AaK2Wksw8gSw6)3}m
piP1t4syj9+#j8Yu>9BvnS0DsnY&y1bD=}t}edYc7@)-7=8kb}*xB#f4a!@SzCh#fFqTnHQz=c{t
FKH_~j9EGv-IH}P4j5zbQs;KZyF57GJ8Zb$>6)firm5bVrg|HiGK<kNfcTuwLuXxDs;;#ddQEX40
?{to$J0b301!d070A1udbcv~8g9nT`lzMQRV<Y3Ea#Y7HFSBQ0yX?4@0bUj-j%&=ND&(Hf<EZ%UD
eJt3&W8ZRme)inzv+R(O)ORv`J0MMsXsx!Px}Iz%@Fs6rmE|s<)w}lhrC%A}2SLEf@1|N4T`AW<W
I55nWX4sF?fRU<Wm4)nt-QT3}Zu#77+^yxaQSTF@!(XQ(S&P%Z-ec0<0pIlz;0*@l?S8lU6%o#(F
Dq?#Nc4;TlN^osI8Aj604PxLjy0MibMBIVM_<h}h=|LQsDP%PY}Iqql|s6_|qLK0xnV@{JU3#;_B
)0}+`G1+>X_20ZT*uSdy2WkwlP)9#m!htxknI0+l1WDJobsmX(m)4_>Z6C@CFrl#BPPav*xrZMrw
I+EP(m0S5={_s)&~*rffuQm9zL9<+)475d?irUWPz#A-`_*)bnL&!9er4APT!TB><aiAiU&okk%(
)=U17K^WQ&InbNT&ECydc!9!861l7;kB{h8foibx`9q-!y6C{q01xh`FcS`(RiUp^Zh(_oINeMW9
dsX&XgCnwTAr;g%Rv@Orq!STJ~hhiTF%j5;@$$!+2yzbp7!?;2P*mWe1gArHHdEwWf<9;U(~6b)o
aI-|HvM*$`W4^<&~hgZ~dA~hKWld?%KpDZIT(#ev$kP_4rC+}zose|7Y>^Cts)dSBcw+v6CPdqzU
65-*IwEyqs;IqOnjp-8aNTrx|iG`ew+w5eKS1RYCnscj0&J|QUtk{YwLRj!ASshK|+2tfA+m`|Th
GRM!4$O|Yu+!+Ak{AvcN~D4A?eZ(kMv%l9cZ+G{B!{gX<Jc9x6wBERksUCzXJyk-uaQ0E8T9B@5l
Mss193_FaKdBm0h+6MqjkXqU~8bZ$qjd+jBex`Dr32G5+Zw@u1o8AG_}GNI?p)B8MQm{WD*W#_4&
F-H}H@Lgd*?zlXtI<pPyI;y*84~;{|(dtG&|5r*p|s%Ijg(aJhAQk2t3|qa04Zl<bR~M&+@!pFlE
FW5ATqt2sT=D%?tYBK6fq&TJR4E37X-zH7p_#GJgc&Q+moO?x-`OPMBMo5b==4us^M6jL8zXEYoO
w!Vr<oY=gG0?Al$1e|}FQhZKUe6OA7(@t{la#4!t8O~r6YjL5DJrZYr)Aa_-Hpprd<FKhIVcVvZO
AN+vzVqEzUwsw)aB}?O<b41iSu1nc?{@hUz5eOs{n_c;H|G6g>*brbFHX+*m8H!k^l#~*B-s*Vb!
5gpgL3lDDfA~W$ptb^lizfh$SZDAiqq|J+qwh1;Q(J1cFUp;$Uq#`;fJQRK-bD-k)^q#^dOKaT`P
$ZfW!|v2UqKVF@{&dcBuul^uVGH!<?oq0Rq!~l#c1|O8$PXP;i_I7NWl^`TJS^-f2ZJt@y54a@fT
u?@y0kxl1?0si*ODq_Gs8nmg*TaPRCpt)Hqq<Ldi^3Ewo}+BKOrTR1{~*ba_Vh#ijzixtrY((0k<
%jhND_4!Vz7Tp;&f&)<e!|8Jik-vmxphG}|>^J(#s5{_yW}DO3Dr4dBGrucU^?$rRqw7LuzA~UOL
UTwmgU!Fd^OQ#@`ff6y(O12Ct10V+FFPnQq-Rq?0xkf1WAA=1j0}szMYd&`F8(ZorDpK&L0IFptg
R}e(&g=e%cR^>x>{A{m40?ytoS6ixwtUo)x8sCj)ez9e)GR;yO!RzVHo^Zaw!mFsgb1HrC1MpUy5
GV!+^{%+$C#+rEyR<ZL?wjef&u3EjPii_0YPqO^XyIk>W>*e^<|^#0F}i^-}AXdYVTE_q|UPqvy!
pEtq$K7R*kkRTAhj{6rRw$L36&Ghv8q!Yba067#fq9%sT#duZ7h6?=WAlt|7dl^^y}Vq=*&#xxXa
$wW#f1<Y*sx<_l0vHg@9xrRz5G4!HQW4v!fp9iCUZg6K^EzM#X24uPTIWo%iWUqGiDjwA1*>7y8y
s`Cb^hmZnZ%*u+lRa-5X<1X%2u%z8hT?Vp%#v@peUKP{S^N*rImewyMYg;RI)@E7Wh3aAL@s<fo`
u7f*ginGa3GF}Zn^VooIwS}jbD!WXJ9To3q6@HE@|$(_;jAJd^YWBcP%0JL^^t}3nKRI#`?f|zeF
J!_Hzz<B}c{cE9h<~`(x2mA@YpYi@V?;FptV{y0>Q9DMan(sktslA5faf?{QU`=}e~g!xGq&xK=_
~xcI-+86p>cAut#`^8z~X;o`lte$j`Uc#LopP4{iN<T4~GAQG$=U>}x33Q9(n(`UZ|h%9yuR|w1a
S{f{JOU#;Mvl>?&p#^EON2vDD2<@I9-l4f~_WlQ?OlPq^AUrl?=URka%ZD#_0(0z!5mH8O&J-wG<
xnz$D8~xd8bh%l@X31m&iMaae$v$XVh-=8Ma%2jq1Ai{UtE*Ipk{TY{Vc{@d89&~%o7PO)YLcaY7
Vr$bHCBhJ>O0_5;_u`Jh~HI4&8KXH98+X=ghec!GXH(6$N0emE#W2CR`;MA%ayqHCQGeLcn+dYi1
ji0A6wxlC{&b1n%W(rJ$B76g!t@^vCK8%QhA5iCy67N}O9cCw{z-F`k!f7)JQi?GFb76$jul%)(&
XAK;#2n~j0^vrX(+7<Ae_hK=hE`?H)HTFn5v<CA1$oey}RtG1Q&0RsR+khtL$=|{;z;arhHchhdk
*1j@+1Q(upU<ilalJyb@J`q`S#bB*r0Kr-+lv~i@>;==`;1NMO>qA9}Xy4s1oD)fHsY(JU=kLU)i
A#ltejOu|+&k@+t)=-cX>OZ5lVJX=J`Qo4rof=;yt=42X2NpiR8rvSStwk;Ff9Nh23Do=&d8E0B;
}?)o;bT&#U-pt4iVa#g8>Gl*BOrdm0`tE2o#GRVHgER@PVY@5J|J%NvG-V+sy_SRL%C0Y_^xL2Dc
XQAoOlE=?Rfp$x;HUfwhr_1pW`Z4|ZX0(_o7{ll20#n-3>mtrQN>JPkc0!Y+d<id@tT6sdQ1qdBV
CuI|sshAg7sCsmEBi~&WZ%*k+Cv)3$y*c3CPJLJU&(jS#mngvG;ec{n3;GK`a0eBD1KQgrAO>V9J
=*0_Pk+@+eRe<+V<W3Gg<%ToSE?%JF&u5^OOlYss8lrgQr4gqv`3G7cmS^roaV6KW5^$uv;rgG(1
eC?)THia3x%Yuqf?qcjIIXPC!Ftn?o-9D_Bem8}Q__kASlBfWi@ND*m^(lgI(VV`Tww9xg}E7rf@
jiU<r!u>^aIC6w^=Q*!kwCn86<5wtQ18sLI7ZBMIu=pkuG@a@p04k+mm}`e$<uxHIfYYi*dHjB;i
b!c=Gs5FkfDEGFvlP8|wMT4u$iD!Izi|6|f`|5WmCxE+edIhsc#hX5^Y_BBZzoUl5g~R#BH+?P`X
^)Jm3w`0?$R`t!Rt=h))%Jd>_v9XQE>`Q=BVMi!*{yU2~7#vKZ)8-NMM;$kduyd@O8t_AyAa~G^@
o3Vh5H8R-lhvJDKo%{D6rq(bq
