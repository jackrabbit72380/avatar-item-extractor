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
    sys.argv = [target] + rest
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
c-rl~i+0;avMBm1J<9b2j7gfLWLaS>pDo*RqP_iEmXb+^;$a{X5@C}7hX5tfne1=B_3B1<10d;4X
0LPBy^bQ0KtHRitE;N(@!MW_8|LA1G>@`rd$Hc@?|t=`N2_f4=qgSgMaivNtn+D_>|Z9Ad-&hWXq
-+W#kJHNKF>0hu5y)Ls}p*7l4Vi;J{*5)=jm9*NuH{A&;PRx4I~%SI8*SGPa`#tvn)<-)GSUusq1
t}5BFcH+c>)G)0YLbp|U((MwyDj@l=J_GW=HIW%7%<`2NGA^NSD9)i_P^FixVSx|^n1q~745)YUA
7>OnkF`wi?fRO2a>!g0R-`_HX$I$uD;Sv0v!sA#69>1=`{3e{Ddx3KqUq6jYPZJJN<)ihd0(BEn{
QCE?=Sy2P(a@Ff}4^*7PJZ7`>jwX1Sz@+A3uHyM(7R{q1hmu!o0g^gdEkhNImth`dj~JRQu8=jMr
7W6V!$2145+Qq;+($_qex0dL(K3l<kM6^{RLUAnbr<JTf*4FpO=y9Z0C+X~d=E=XkXP_eR#Leuu3
9uz^|WI3p2157`kQbTJx?cCI=%X+=J2%*AF$~cX>uJe=P<kQ1^}GpG?Z)_FBb3&+wNNfgW2J0S~z
>57BCfj878nGrnhw*%_f=ZcK4sC+i01`W59(+s@FR_Q28<rlbabl2wp{VU8CFE?_r69#|I6X`TI1
B^Egd1ShsmZs0yHYe)jgI%3yF&Qza=Q72q25j>~)<->jBVznJwr3Nv_;T_)Z3lW$cxOQF=g3RVjM
f4BX(E05Mq)oH_6`P*ljj=BmzVWWT^H}NeDH%%hIo+Jm<pI==jfC7M40F^L7)PwHY>H<K-a2bcoW
ek-T(XxdQi0<J<1g*v}RD=fha2LflQ$(CBy-X0i238^9>mtn<^=Mr_MYAYR6BW=Ba3_x&3J`U&4D
VDP&!e_NESO)-Xg6FY1}?Jeal8>AYowAWg5@!7K7@~Pl0Z>F%4rN+7B(J&*V+S@3D*9OwtOgKBQm
1$bP@spqkF>o>t#B3Hj98VLP+Jbw0~R1c^)O|Hk_@Bxyou|ag8DdSZOj_<8Fq1HscDjFh@vTCbHk
L+K)f+yJ-lU@OqZQo<#V=b11%!mN0mz1}Gj9R2T?J6eC>Pno!~ZVcIyAaCt-MZ618g(&BBJnU7h%
T#fVM>pHVqf!&PX&d<JodvfvPhttvd+22pqvFhA+4?360^VjcQ{MYD*)03B{AM~qk4}b)i{_bx@;
iFEcgY9tnw<m8-&*AxROd>jcb-8zz06^o(<zAB?cJbi}3?oFyn#VnSd=cH}urbWTeSAp!+B`bIN9
WUU5xoPnT*g2H%)7_*PSD3ZJ){ni?!1ZeZ~`dsV**t(=shZi^#n`3Siu1?f0548<wXb^!@NBzweg
eF!tV%!%VazQ`iA=)X>T+MPVdLj0;k#N3(<u4T=XlTegE1&JXdgyqi|mI{XEXk>5+8E*z@}Qc?+m
25L2uJuaTsu00h{_InhZzMP*0I$pJL>8V*7rHSGcku~B%gMx!{1^U)~4v!$sJBzltg51+R2Az%ak
@!q7@*LV&926->C_;WOZL1yp{2vb1qs&CYh-S>DJjXz1p$!bpJ?at$Cr<aGOkb36zVpYO_%P__h-
>l!|9>NO&wOl1g)E-P!@DP5%vHxJwxZG0@RA6;g45#UJ)M(ffz!lg$erv>s2U|yp?ZLS{(S#q)Gp
u~M*YLp0kTZQ2Z{ajr&HM$K#@F5>vu@U;i?_3g%IoHf7eKv%Y|`szKo#8SKvBS@5n>`#mL4A9irb
}fq}9j3=Ow|BYT1>V)NsQsJ`b}`P(0|Wr%$PF11fdhGDPV0ToBO)()qJzYJZ5otzNt(U~v5tdZ3>
E%8fO!Hv*emoFVz}m`38hBA~RY-e~Og-#MsV1?^=7L^P2x`e-*=9Z_+Oem>s80v&C|x7CsIQSPXW
aWW1XFJXMrD37LlNF%X_QL5KHtf;u(+g@?MSFRXWRJ_$#P}K6;yan`OWP-N{s9RWbdC+Yr5L<vvD
))7GPz!9g&!pik19A>UA3=iX+h}+zbBmZm1(NcJOQX5o05W0~+AHE)V1b`r!?C8H>St&4%m!1VG3
X5Ke!|IZn2e*U`P%fSQIE||YqR(!8Rh9H0lt8CVQKvCX%e_(|49P?_}@<|$Ixl~Y3Fbj0b@7=O25
pCgZQUt46^3AdF7tR%qF(}u?mwM-cGPMFgsUahD;|&xlIrb@57rk31_ej(V|H#dw35VFdj*;@$zZ
5{a9x9pad}LceDhCbA<;jmued%@s|gOHM-xm;Ck1BpLZz;lK}}CM(g*l>DXa?mGzfb`Mhft;7Rk4
2UUXTH>%g}RF+@Yln<Z+$eH`?4l+BzA$<Gh8xZ~;S9kllu9<ziVkN&(#)z*-J`~AC5g1rtStS|lz
i84oau6TDu(SRFogrGnpHHMPu$%h_io~6EyZ65dO<UczI){c@u!$p<{QdzaVgxdbih#9RlU76pMm
!#e^T=)wg=`X(@wg$v7-sAFJOX(PH9|0skT|l3txo$%x7+wmrHd$Oi5g@UUwxg~%}vsA_UP5S4{u
H`&fD_|0DT{2b>M@E2gXBgHDdu0889=fD}c;I>lCc!P!WNXg37Rafs@v71F$ca>0~wLmggXghU0v
ODimGaL+ZfC`G(<T?TtXEjfG(A&8@7fT3MG``MkN6&sD8_F0}%SRbaW$gNN=G_(rYW@}HgZpWX7G
q5Nm(a9jgb?|LU8H}eoVK6@wG?YMp3JAK}}ecnUWd#BHUI&G-GKo6hkW5odOaR9LQ+>Y-{r)@xmn
+z-d^SNP5kUt?aS#x$g$1{Ri*Trmwil*!MKAN;>uNAmQeeZfeG?mCKRQLE*2#Z=eG#r+i#0Qt97J
-L)KbEE{$i9bVo*Y8Ocq$vqX;kE*I|)e)v*NJkLsW%VAm2fKVqJG6nFQRb?Ltj9ywUkv<koO11do
T@9P%m#&gF>;U_G|bRG>Wx0`pBi4I1^lVzH19?WMC>#y^E6()w`J@W6ivP^6RmFtC*cjG-^IGQHb
tA)nWpl8yo<jJjUdsP|P+sM&ef0H?<vP|j``)$|EYD2!)nJWG)iWQAasr;Ch8I;-vxl(Q&A9V+ah
=uYK;Go+*>r3fhoxjm9~P^X)aE+8Y0jYs$$6;sq(jJiwKQ)emPN=V1?Y^D{~ZF}1Mc|2VupO6n54
EX_eP{`fBu7rhY!{nAVbx$qTiG>6Ryb7=}8W-IE2vw!T?w=9EkIgityGBV900gfz00()oSJ<D0E~
h0`J@iDOC(Q*G-n;7kTp)u{`e(TU4#N>bNy7jOXl*I(qaDIZC6geiflI@tN(`rYcpu<LQyRc;idT
UKo0dgf;R+&Rh0A5Q4y-Ev`l2ekZmj@qOAy*=C8!qa)IQ(0y`3mpkG{bud^;>UZ7NIY+i*_NfsC+
UhQ|;(qfR%&MJNyLI6M~rJgE#XBsA>-1iu<F6$!3Z*Voa~B|oRchEjn(5Q7|bzetUO7zj<2<jXbl
JNgT)9`5i&t`^s`G@KOj7~u@`iAzr1@uQeWGUy)wbl}zH-Y*y5f4JOpRWP_!uvkMqRjzt|>k*etQ
MJ#F+UUzep}xHqhh}7Ux4i=eNNC3T7aA)8)E;ZOf4cip?lr1)u1>>jL^3_z-RJ>v`-1zkIL~L%2*
rdj(Ip<+CE|%iwXO!eo<%d=H~aFY)MM{(h!b{4Lx*(NK*OqZ>}V`2RK!GliVA=?z+I#sKSA#U))J
QWFZ=?wPtgpX;i$d{+(!nMbo}TUbL$#54=rd|pM846mG(O|!02h2H(jEZ?-=$9FVE#3;fu3WR0Gx
JHyZ!3QG1NLfsv~)!7T%lsi;0Cy@Sy1O^!gqXM1-|MtCcEjCKTVJm*GCcnB?gGAPhQN{9fk_7hS~
4f*<(iY7{J+N)C0enDi)9e9f6s_yL8tGe!?eByUsv|D+SS->q`=V>0!<bsDA|Hc}7QBLTi-hV!zs
hMGk21+fGxv0qY%Njx<Rx@PG4!C5<I=am9&p6R6CSeo#rXG8v5-PldOwERKra>ov+F?eFq(05?A{
n)!beA01mq&d5oSmMYswa=}4k!ti>+YdyJ>!e#rZJ7_9=1@A_~TF5+HK?=T`((HtQLyWuo!d?^;f
y<6+)@?TX?;mFl`O^zUrCkb{bT?`-;oVQOTKQC@`6(_Fug+WTI%pqY<K;#?gFJv_jf7)N-|Y2i0v
r&$Z1k&@T7l<Qh-{s}{q9sysbiC<zmTH*PbeW_VcCeFU@a9k9|th8LJI0o{HqjEzyo=X}*Y;*AyX
A79qwMR}J*N{TaT_SODAiAkDV2KP~tW+24m<0+y%npoi7@OlPp3d%W)_#P%^1SG24>8n|Krw(~h5
Gm-sR_u%dfMQR*{Q08WB%1*I__)zj)A(iz6hzk%EZ{=`u@oiKV|CPulUDZ-=5rS=sBM<1fTXj^Pw
?*!XitL-RM1*w)jbr$f&1=BuhUek{T@r{{BcT#Df~H{!DbKH3W~0<@ga8tb6AG+h#m<`jo+29a9H
qq7T#opu?U7}zR1@qo27Zf>*$D1pbDAodX6a1;2(5`g3}H(?ANd>WNI=U?qP%Mg`$^6iUUEx5#0i
eWOnoiCQfr{s?jDv&TX%&FSvN(ur1Sc7BEcyN<4-><rHy#){%}J9@iqY(xYL!A=alP6PaD#JuyZ8
p)=BGO^#r{m{uC@R{QO8kC73$P6T)pR)G4z?*hlmJ?;x1=~aVj1RAQwKypux%RSR2ma$-Zxkr=3r
}TlI&~nlv`h?HOqye7b-`|U!JzCyeJwALK-0BUCY*TPcM6v4<#T)bHal^qL<kWASqMAnxmUP|NQ2
$i$5o-1TU4t8Z*rSIx`0xN9UKJ&;xTHmYSQ9at+~)xc_YO|NNqC<>=AC<du`JkCvDgHPpn~TwU^;
M=AW^_?&{dwIek6c)?hs?u3K*9oMbd5)%`!poW#hOUxVDLN-iS$3vYIc}sAowQ4!+?a%k(^1v~h1
{L4aa;R}UX%FW*@g*Cc>IVH%G{Fk%AXA#M?t&;%5de7%T{z2Ydh0W=);6&rxxfW;XaBLyw!vDX;%
o2uV$b%)k-X@r@RW1xK49>SQ<8nJV@0;pY~(lg*~^bnWt(Ia&Lt0~07JhGYL0t`_58!Ucx$A2s4j
kaaD4Y33jr$IR)Aj}CRKrC6BFSG`S3sT(#{tpJkH<<xY<1N#O)%mbdXg03asKi)?$xQ?!wwZH!dv
CqHE9uy;uZhpVD+HLsLnz*GCt)-`vroJ}1JX{AW`c?hOIjyfi3)vF2**#@W&S&W=75UBl=PSGuu-
leW=kH!F2A8tuYZJX6k=3G8{up*MM^o~{)gofD4cfGGk94s>Y@qYP6t8o1QsMl7=_5K#Q330IP`?
T9T(6B^nKE(=nipohmIcCb@aHRqsNUQ6dJ$`dygMi^f^vZsz8t(^}B~&ftmqnz`X^Qt9EHRoBHa&
^0@EE9a(=UgzJywRDT5wKpK1Gt>L(9Rq44^_N%MJllwZX!CD7fux0^ZTwt&I@ELcYxcSoci-)r)C
rhir;G2akK~ur!E`P4xAxP}Uh<4*Dw39})Of?8l#9VX+pKzTQUHD75uur(~slbJOMg;7(u|uo6MQ
Z(zv|58ZwH+0m^!~M>1Dxf@FOAJEESh-Gs2Cs>y5CZW2t2Io0?Fe6j{d&75Xce{BE1Z95FiEulR&
GMG>{$HA68c-%@}SpvBbvRRx=d4rvZI{E!5;kuzU2U9(<xE2S$Dj_RTn+3~L60%I7OHQQ$DH?#--
G^-PWX;`pGiS)4u{vcrNW%0jd$*HT#^e?bChs@tX-&)~ItEz11MTi|LU^ija>+Uf&!1%d^zIyW$;
hFC&$QOQEUQg>QujN%4@k@!p_nQ>3ZcJW8@hRM+G0h_U{9qyKZTyb*4-Yv-5e+`YTqpM{Kr!ssH?
Pr1p@hjjcutPTN0NIIKZ-tYIzE2|#UfRSa<0TnUqNBqijx1r1TT9Us2YVh*qv%uBwU%&iT5?6j1A
iPCE_;YitwICMSr5znUP0KU;c1wKdA=;x>T++yaxMz?MR)C+2xWQe9YEbf+@gO|46(@KluILQT9r
g9ah_?pWZ10V9~JvWYHPt~C<={(FKC50cMH}czfe>9IN(|GMk&o)G|a$4Bb8v)0dcc~ey_MNAPnl
ewk&9#dx!cC=E6J7G2v7Ex<Y@J4*9r{qU5e&tJT(0e_C7r)~i1?^*zE~Ka>@9s~%wAyL5d^-9Y)N
5l(q)!-g@y836scF8~t)|9rFwfwe%lMAxFnkK54KP4V$cfAm#Gqy((EJipL>DOX_*yD{q*4m*K1>
oT4!tPfhD6vAFCuI3NsWLyZiE1^q^mAPGM8v|T<d9&%I{RHi$G(BLkOBI@8zo7O{+ExzcQB{n9!P
j<`<I)Pa`VyN5WE;P49MYzOxwCXEEpM(M(A&LahF*ctb^#ew=~}>fh9YS}E{mr}o9}C|iATB@t|X
qD#H3i)HiDPd)eSN<BTLjPhU1tWP3h7ho>VRm^I6MqURpx2*|d!(HJ~>vHyO#$5^pKAy4|gn+AUF
!GVZ-e4FZ<ezP`b_vK6M)4cn@*Fri7ae1*!>Fd^^3HJty;h;9B^Es;;tRYrD6n(Ck_PvV$x(gHWN
SqxcHYR_FEMKD&v1!X%h;`?Y4=jqZl;mqd1!ayPNCe6O%MhgM}17(B@lQnzVl93K{2q2ox*6QOb`
P6nUoILz^rVbxJ-luKhpoI0@U;#Yaelr!aW}a+oOS{B~C-;kJoRf+s*zW-^dw@3$rX#ZIBF*3{`R
7c*#=5^8o5r@=#W7Y<y$2IDNh9X%=QQRA?7$e9v60`?W@hAp3ar624XB!CPz?v!-h??><-zid)8z
yXFjT^$CXUtdw9BI$-H?G%1$;4=33P4VRu@pzwrBf_U9`<n6O-9-pKwh-B%Eu~qaS}#<h(`q3d|A
HT}In6lEyyvxna5=I%uo+*1%L(V>DUyf#{yD3Ldm*X)cqs$zcUav?!Y|>@5&7wS<MayUE7)fGyI<
v8s~i5g&^B-NT?l#Dzr_SFnx6=uT+UScD#l<H+GbRT~;)TAu#xa_>`&hF<8FnH#53_!85@1>%YIr
jIk)iG#k}<9T5n{)7$TB=8CT{e3r`LNTRo?}!NUHR1#N|9<HdZ^@Zt^9+%_{NgE6C2NBC-Jf9HVP
X0GrQ>k6<xE8NvQ-QSlucN7B~n~@9%n?H9O7yDDEPiNfo(aQkh?aPa*eEmtf}^U#s->hJ}eJLeP3
5u%PPq3^xMk`eW)+!vJ*bFSl#+hKBC)@|4>}{y{Fvw76N21Pl*Dd=p*nJ>t_#X7|PY}P^#pCRlg^
*IRs<%>#x)+gj`{yOF9iUJ>!|R)f<kmFkvTW)OS2S+Sl<#90v|=asQy#JUHkX7KW87tm>l6awPk+
yKtSMXvWb1rpN^?BTef4Cgm=gD>3IpY9G8UrDMymL)RFV0((IH(9JSh1J54L!cvRNXfccV&YR+(e
E9yk3SfKSWpi&I)xe#{z_lMW+UktGyfcnOfpHE>Q%=X@*$NG`AL+;gK!N7KWZ;lKMq!eDttR2}6R
NiiXP2QnH1lO~l0>B;X5>u35j#@&mChuRf^I3jrqyTxyQU+1gyKV*`;DO?1F)WGvyIUCnQR>9@pz
e{Rz}B!$Pm7XL{tf{QfW5<IJZ6BJfpp)u!1XsV?NP~O1q|Fk7&lGN*xOvgOQDZsfiQvF!BOH@Qo-
raIoKBUmKfOHHf?lqTVuslF@PjEIRN$P$3tc-JINyx`&UDOMR@ef2^YDv#q;x+q;{>`jG075o)D6
?QXZ-?zDRc2;PYHmAVecg#pSEW9Jw%c84L@$_w0XErDP+mRYWy(+Z7GoF}&pf7O60>e|?n_m=3We
!r-pD!2#jU?_BIn}{eBYz657LcxOp6JRrXzIg9whP^2_@kjoH?xFvrcc7p6^OJEDeFS$-CyhdjB(
ILjuQu}tQm+_QxlL<)Mpf0=E?io?0J7fO`31We+5oyD+Ba%{E7!ns<p!pKyRdwMD$nEYp<9KJ1Bi
oPThkJsOjr}KuUNMON)#srPw1Jk7zGLPZstqL+C`IZEJd53R01{*bG+qOhBGAwSbr%MW9-K={Hat
xaF=X%WIOpqgg|2v`B*9<(8nV3(JJ!00p3^Y<T{Vo)NzJ(py*=S^i*7EOBb^o8R+;Og;^PiuDUhX
-mWQn-v*OS<LUEtX2|3`nx{+c=_wC4D8QV7*{2Cw`|ZY#yJcKmkXWqpXq^#muIEC-Ei0yn#;8l|x
k|{tzwc8q4GxXg8|@(*j(!Bg=_nIbr(f&lqg9-d?I<Hp2A$!+NKSImW4<{~DO~<fGvcMdXyF)eHY
@b{sPGsGDhFh?w+Qp8tKg@=L&VXbB`@BRay`+T#fb@U$9yY06HKCPyo?tdzls9iIjVj--H%n8wXw
tYBwk_%f&Ly|W%$<`l4Zm*#t2@MFeis3Qw2AEfX$*rDc;wtp=(o!s=Y?-+2b^^ZAhchbqvSAsL`n
H$ct*CTZr!CEYAWne4lTl(0AxOUKGJDNb-&n_VYdlYMEcRj_@K8xUK7H1@AXW#{gO!OB;>HgX^ic
1$eZ0!<dfcev%)N$6Y#Z_~B;QAd;+q2WXd!mWxB6foxqPChNEwQ35P8#sLht!N%{}<P8tU^L3U-^
V9p7teaC+2A)EqqJ*m9;(w<w_EDaWM-+7oWBgGlDbepU9^))WgeruRyCJe6x@0@w<QQ$(?SG!Xd+
YXiw~TY|s_Os8-~W5?m+928`tA3!IAt)G8>ko!)gE}bk5oI*&*XjsFW~hfI<WSJ)f<Ug{GZqt)PR
_D8BA<y-7`)_FCiK=;J%>vhB89ic^5sIk$*@CXo)GKE5btE!MRBmCyD+t95^;@6?5fyoDY_|Up>3
FLemxstBTr?2N}mYOT<bV|7T>Uff+%}-qB>#hAW4aw9A%3PzxG>pjTDccs*@rQS>P&`5wzE!h2@8
+4V-l92le3Vu>7PuxP5)VuVq1TsrigV!>j(PUeYzX{{E<1c#z!a+uC+Dk6Kh%BLynlYWMhO(-9Zm
uUu~!QWdG;6<i=JKiTo52Y5wUPhvQigLmZ`RPXcR6)3$)Adl3t}G~=CEwR$7*OraNU=cM>N&>&6{
)`!XBbUVLYPp%QB>3*uYlG=73Mk6`MOC#KMHGW0Tx~hT<+bw&YohkfTj*mtx;X)b7dW@0KK`^{ec
X?S~;Tfqx9-yz=$CXm|4VQ8kAm2v?;e)Y6&jUwQP;)1}jb~ctNVH8Bib~awGm=LU>MJ29A7XQxa_
34Bxarum!E5N5=|iTj*)pDA3dk4(E>YRy}ARUKhW3PwGZ&8I?>*^{9-@<SBbCqufrD?6#pEI_USB
YTrLvyrE$HL;m4GNF)nrU=R<R%KnO>Cd!X`LwmsdlASgyfY~Th4<;OUyPj-7D+s$_=$9B%m5CQks
sW>srxq^GLwH|=?F0&svW||u+CEv{tk6~VJ-rDmUi-L+YMq$C))?T(us2L|iOL#f1ozMmCzDYqO~
X(*m@>|B8U14wFXdhWeH~^C=%^yd^41oqcWg2o%W!#7O{~+Zf6`xQ_&0!h`=(t4M*<;k5ruR>0{e
M`aaLgc!dYYMcrfnso|zFX5=+zwGvvm$wy;`IU^HSqqU&%q%b8F#)p(jB1|0|T{c>;3e?D(w=FD_
i!OUXYJ;xefEdbX6+vHrh-#$MMJKzAEgt1W$D{0Mq7E7#a<Ffj7rgUZL0~*fAaF@EGKiFATXpJ<d
<ul}1iURp*PY`sAVuXfWP0I=t0d}2UQ9~_&R?$ozOf=UARD;nHHa<}e?4by78qQ{;YKtFYaF9R2&
TYYbmg1d{%`BPmy3CSw-KU3z+=(~=+B^zT5@^@a5ld+HV>ciKmU7r_>Rf`(lo?j-FkFfVVVs5ONT
{lA4_tc$J!tI%8Ey3rGj8!1W<zZr>uDV$k*!142g-ObTQQi4C)dv}_uipN4WfM2plx64hNFIz`!Z
O>D?U$)iIIi{JsaWJ-*<ht$##TlR_bScR@)BS4$TXvDXU$+1kIPR=gC3(rl$N@D^NKGhb^$JDvOv
X1{M{I$D`PKP&wKz9I#iTIFZ?dp~{`bY$AQ=($|U|pu|j>&f|Fj%>bBQe58lh#4jeyeHo(wlW>d-
Hb52D6w~+%w9vZ)sI~>3f^pL?oAwNvT&K+A=qcPS)0}9bt}X|0jPc446-FcGFGnLhmq#PRX7Vw8n
d~+9Kt5Xni5<aE=GiXECr-J7wsiaXD!o_xhaG)rQ#&jlglJI)ocGNt(tfWke63KBXSeDX6j>h;kF
52j?G~TVXHd3v+v~Ki=!k^PIi>hxl4v2nOLb6gfc^?sCy8^81h20-@wB;<2=!MH^^s%#3+6kJ*XI
D=Ae6S14rPy&dIk`>Ois>UoSk8*#cGLSMPDqHa3|m-EGz#^J8J_1K!JEp^ZO-TfnYDj`m-6{$?^p
u-31e<V2E_{OaWF+U^+zyTY8NnAuPmb#xOzl11BhE>1v6h7~X{H5Q|EdGo$-rsE&e8kvaqK<Filb
w;)%)0I^IhVv4$dwN_JTqOXy*+h$l@r!$1HzP;C9DF9q7*U!DSdhp}<>4*0p-n}||efr=M{=H1^5
(@AmQR%CSMA@f26-nx#vW+qE1k%RiiX!il=;boLjVii4+*Vw74=auLLIhBZ(?ZL@^VA7RI4BzP1?
@b$RRID+HUY?xAb<Ad(7jBa-mK!uvo`D?IEe8={t>xW;612r4_~TBO1KDXTc{I-Iay{=@$fPUXIY
AF|DQ66s21I$RYOd94G2PLR+nX})mo-0F_c*pF7cv2okxsvXmUj!H6bQiz)h4=<TW*kvvEpz1?>R
4JY&b2lY~bgBSe_|ib0BgEqE=Er|AURHwk5s3^FFtNkPyN9alnDCvs$ElmLeO$Ib3{*tn*(QM56u
g5~AbI8}sBOoQ^e9I&);+v?noBo}7}rz=?*%V58Vxx(Yz_f4_49DdjjQy$KmLZJt^dfz%y$fDBAi
_sK=%B*Sb3ojEf?QGhqN5o{w%{jvMAh9L`n!F%0OaWMFMSsk~8*O#RR9*SxzsxFqMdXD8P!P>%>P
lw!*R}PO_fRWcwh)b<p?y8#0PX|XY#ZwfGQaHOW}U3&3-<|{RO7VX@okMv3}mAflsNlPgwZEFO8L
B1fk-=j-Cs0mn3`7~U3MbVwJ7%yi4K}ufPMHBdV2PVhWqF#Zg|SZBTXf<wK{wGPh>3V5{^MekLgC
8=<y^|!r^CH7{n-QW<axe4txA<5x6K_sF3bx-}3RH3npoc2#rxib6mg_oh0$OF2~?Az!4&0(|OBT
j-s0|wD>%#8X`)Ztx3F;R*PNhp3UkewLo7!iyJzbjFE8|x`u^deKM&_lSp6X;qF2>^hLZT-@B%4^
QO9qQVe*!wi{%6Ov|-^C14Y$1u`L|YVclDf}B~3YGiza&z#1bwJ&ZHSU`svA;(T}l2;&cb%+}CQO
vm11k%Yn0pXAK{b=E(?Xq;4gW|ZRLg+F{ij7RY=dH8fK6;49JVJCiX+gz&P2whO_-v<iIMXnj&f=
@B>2a1tm2A4o<C&i+=j`pv)1N8snSW&B0M0H>-;7RwzBqk*e)jGyX1xJM7SBS_j*FfJu;Ki_&fbp
zr#LeX$UKv1r1?B5I~pz4V>GKm#+EAI#5sSu1<qev{+eB0R@GeY{XZX0U;Ogo^=bS0*;_8of|mLz
ouU86nIsUSoIAf?CT~uD9=$w$fAIqhYTvoW!)*}gQ+WjY;TWxgy%19Zdnfl-(=e#w;lP^_xl6N4B
H1K=<SMVYHxr*UeaB_%88{Y{8M}RjVv1{t$}U)L69XGmUJdFsL4!1SWGOg^8NnExrj@?!t3*MK%N
LaSw6W>7&l!VOe7cbLZVZVYuB94KK{#zu!|U}_ZC+x<W3l?Eh{wuW{Ms^NtHFqJx?Cdp$?$2Ft-K
!VB3)2ohU(z2?!}dxc8)X$l1mTIi>pXxf#K^PWZOJev;fTDg;5%B&r;7xvFE%okSQmVzS5xpgl@&
RYa|0wZaXH^p|S^u7nkUX&e)QzC{Lk!L0rN`n$9xfdl$?g>jSH8G}nKEm5Sk^i*P}7)Q#}K%>vK$
lx~|)%9HaK57)MOM-d}|+Q9kFY0^yKIXHJ=RsM|aKg9%m$JTCHz^+@NHvV$&zl*SKIBKL11&nDQT
jBh?e(`mq;yu%VlrKOF`D|}{SrN{5C~1Vm?PZPlxA&#v@oM^`8)~DsPf^6N+tOux6QksY!HEDZ|6
4Jzf#0N4ezF8+Zn6^V^h|7&k-y3)-6S^`A{T(+@WL4~RBOT&WD3L#o-w2FKO^N(VKbkjseOJIYgR
jpqQuiL6HAEF8m_s04~fsqloua2N~%j;D$W2QxJ=)-BM0F!Sw*hSI9UhW4|GK89T`v?c&25ZA>aa
j@eupSq6M4E@v}Ig32pBROButtVge@hQIr&SSaCLDmMmb7xXFUKWpcnQ4w52#QNFsx+a{+2oTi3Q
1`CdcbEI)^47x+x2Ek{KZ2dovq8KNNWirx?CY4o%XBMs==&KlZ^42Cf40RD1%Ml>SBMp{V`4o^Hx
qOG>FqPg7dHw~opwtp%A5e#V?Inos@gfj}Xp?$ge{)sb<JA&(PZJ3AGLw}gPur}07tTIa4hf46`e
-VX(NP#os3}ru;JYn{qK?02qcAY1biWGln`omE!{B;Hx1PETedA=&CB%TM9D;~idUmV~+gfF{WM(
@k2Qe!4f&rwn8Qe<(6iu|72p4bc(%&kH|3N9`1{F*pwdx`ky%HdDU2in}(D*DA44iC7e*b5k{doM
dYY&-6S)nKR5|MYHyEo$rnerjwze&-Yx~cenRBr5;$?*j!V{AiC7a)eW00+V)nHrB#U`fOUi}ZHi
|9JM2y^5rpH3sxT3Ari$<i^&<JR_SZ^@7?G1-q5x2V49)6P5Y3aVIPC%<2f!S_Sa>?59)A9de7oG
(I6`YYhix`<)D1T*7n%zcP!67pmw#{HxXl?xR&ul98#<!)wYnOk1k^s7G(u(F8BnEk_fZf_cIOo$
s2+6H(WJQN+f*u)QlAQPh|R!ZT#s(dq_0&q7ovlVJtw)@P9yxo<|9LX+}Kxf|z<o=`|r0c~=@#|V
AROTo=dDCi}on|Z1Z`c)C!e7Z|D0dbnRKpsN!^?9CAFe?7kHJ^IslOF)9T2Lz1Uq^kT{v3Z1a~Qy
CjwFW;g%OlNb$x+HBq#DiA;D?qIm==XaPDLu>FrAH-?>T`IwCcTBN^5HqoR6%O^)J8nfv#5B&_i*
A50tenR6I(oB>owx9MX5`1rqrL8tX?*t$Mxy&C>@^n0U)_^1cr44nc5VZHXvGF>f#Zi5zpBRgZu6
lIfx@95dVUY$kbJm3?dg4vL$5vkF35)~`7y?ss%QAhPe)^?^@>_kgdQE(M_7<uE-Xv_gnN?ezIfX
5~YE>fFwGJ1^MK(Ao4c4?c&8=Ueya$`g5;&+o?f{Sa~<A?P$eFx<YN!+5aC)Qab{kMsy3rgw@fo2
iKUH4G#V2i_B<uo+d(K3v6dX61QdDr+RE;1o#9Hks&8TIP)UH-7i@#-`7T(4%W9iG7yH{7-`5FW?
9l{@u8$fNPG1E0F6Q4h{aP|^$<TgVOD&s{~DN2}VHC%FGwbk2lhi8pi&=P9aF^cC_QW?H%d3Zzyp
k=bRh$>1*cy2KhbUArP({U*xMZbsMt7k7v0^TEUz99TS<HnA#i46U!!PL!*8&~-4djCz%^WdDdT=
PsrhJ2TWYW*XL?$CesakQ@9PuQ^>j!;IzTS;zRHNC1g##lb$}S9s4V2K=Zd0<P-qyNl7uPbU{AA4
tv5r!A}P%=K-dkdQ};Z8{VhbpV5z<a}p6i_nG@eHp@pWcoH=Q{aG4lES(~?lM5$Vbpa;I?;L@WVB
j*SABl*>YQMU))g7HcM<0^ib){IqP^ub_bOcG-TiwwcqI}59M@E<ui9-G8l7kW0&INr=H&ac7Zh6
ga__~vw`AZCACc*mkMBXc<I4;z|MKko{p*uo$kq&vvF;DLUDEM%dmQD1y(%$dgl4RNym-~>9zH*1
ww{I}ja{5wygn_O>K=aEWra~yb*aNSuAsc%!b7T65EkHNyN6d1MWptq$=e@aw=m=ZdFD?{4-$?cW
M5A22%q?A*znOqOu<|P&nE3xcsGDoeSY23DU>cR?>im-W!uS9sbkf1wiPyk^@nXX?+TbP$HWPuxh
uHxHnY^0N=2}2lp~;nvM1JsUIgRufjF5>(>p>c#+)K*DGJcV=F;UI;J6%eg_LnsCq8IzQp}h@@7S
%wT4*iIFlYSk+-HlcLWE+Al)XwTDGZ`-sz@3+?JcW<61F#ejBAvWcVW*BR92V_H;9woglS=5#u`C
sxPE3FtT!x+L{zt5dnc3g<|@t4s0ER^VZ<ny)q=Y&;fa`EPz{L_OXLMG0#o&BN}_WwO43EG<sFk@
9E;u51lk43Jv381Ca<IihUcI3Re=_C88vlhe6`pYk;1xHEKZ;%XJ$jZ)jGq4YRRr;lE`)nbYf^LF
yk*SJsQ0<mz{>UWO~7(Ms>7XC|HrFKwPF6EQJPg#@^H0{TFT5MXWRuF}B42i+V;M+yz3D_N=MZ?}
*oU9Vo?tDaY`{-Z124W3w-MA=8xkUGA;IeY?DUtNByMIZ%4?D;YmdPZh$Qi=Fdscb>kQmzc!D(~_
*-JQmP;`&3!vswN_KjnKXcD)rUAQtxGFFn)%XDJE=I6ukSYga2N=da?iQlOCM<eC^0?2Bly-gq~2
7>RexsTUe<DwP+)tff$*f#u)Aqb8=+mC@^GiP$9(dDu7tpmLm%tBlrx%!^^?flG2y7_}H+}aV_d?
Y-{Ie$<~&tY_PHOf@p&7p1cK${2?liqtFykEaM57CF<VvXnYo4M<bqGKrQ*)&)-0rfWy9p1vNDy!
ZHU|Qr}E7y>?D{^nxW_O}4rUmR}E^KI>oZJ;LkhfBvs;h_z|K@9y>RYpqFOz`*t)fL1nxoKg0Wfl
kaPzSmq0JZk${xbXd;e}ow26*69+*z05jxEhc{rPv>qPq*bN`C6NdvGLW!It+;UvCcmezkL}=#4d
C4y_2F%`{Ws8pwbDm`sS2E@q(YX>=Ot2AeOAD(=M`(S#M0%XrHrRl?aRGik7TJ@o-$M^pOU9do&J
Lnc%4zbCPPaT%HjeY9ukodG)cz@+U(N`PgpxjH6U{&ar0WpH#;E&#vOkpm30O3n_#I%Tm;L0>aWw
l=~!q+d+!SWgF(yD~av87&qRaYut(!HVw-;R~&@{o`=$Kg+EG##O`%f1VlzVwe~!{ja&r-p*TtIO
&2QMtJcDJ>2$L8a;|%`j_GnhOQ&D#N+z=#TW%nvH!oGT_)#FJqrzk=*uakdjgUA@^qySAV-98$t}
!+pqC6^^kvA-Jq_|l!c9=%*c`_!2f7(K_tzHvX${6A}UZmG()fOgtzG4A;ZOB8DcVcJ^-o?VwW>8
68p&dp_`Q+;O!SbEopz_k^a*rpp=P57I%(LX{xS<89V5P<&BjM3C`eFoPK3=Ax+CCK(QS)%QHl~0
kLQ-M=>fB?QsFn1o(rue>QR#KHueEjnC;M>M)@QK9hm=8JF+lI5A-6`ZG1RwY2$OQ*{l;>h2Q_<z
7AavI0~(XX&NA*IOI3<qMSi^YD;;eJ-WgXhfV5M_4&+7mVlpzjjOF3gC$-=v$FoX!yX|qXSc(31A
5e3v+eZCLt#0jQqR3*Hz(~91cD&)5I84sGt;50;pz~rdbn6=zeQIG)<+)!uR68xlSFFpUfDlc!25
}MO%Lph2hP#A=8`DE{j5h+QD)N+5vnb4Kr@HOKwzHOmi8vtsBz;+#0<VCqi1!7DCgb#Tw99-}&GP
BfF&)yoq{%uKIL+OB+nmG&nV2PqSuZHzIa<sazbc|wWSb`*BEpTl{`=2rJPk>;XiRI2M|R7^rX;N
^5;b!A61N#L)zWD=i!q53fJBKnXLInPf{5lAs6H8s_Y4gH8ZCTNFlk_kZhD6<#w5jD9%zy2rMYjE
0)gp*mM07~;2vvK!~_-GAumli*hE>&gbOgx2BaK<tT46GZxKi8-d)2vgAqVs|8o(sddEC1U71FE8
r@Ig8#ob-GC*o`I$^3;McwP8pmCHA!mlc&BBm`e3699{n-ti;sEhAEJaW;rsXneIH|(s37%lpo((
UlSrdE_W*lNWCy3s&Q_b)IiQEzi@`yKfi$^&JIT6E&YS!C^G7cL*j3q@FkzHB%0JpsObm6^k{sf>
|qn9)v$6)R=Sq_tvK0=b=H%1QkqNOaHuAcsR8+<S&!f3puDn#J#BM*@wLx<u7780RzE95o(jmHVe
`1pXEJblSwCkMkymF2~!vt4Lf`mytsW0coPyb-QX;ZzQe`i>~XGGeT8u7fhyvD8W0YxIC(^WhOMT
DgmqlG%qg)Gs0TUVz)VjKo*ot&3@A%;OQxuvFK=5`dN4QJD+*lsh%4cZX-Uv=OBi>3Ic9(e^}Kd!
BECQp#bEnxR9@mLw*UubS)-#Ulv(FgW^~pJ4wnCGcSBg-|f+}DCS$X<c}|x3wy0W;lX`imrt1|Vq
dkNCz6iuT<1>9qf@u$J9dh88T|utIELxUE=08dL?@^Co6<ayYOw|D7o2$7kMmDC^vaudGpM&A`3^
_s<_;)uMDC@%vfU`^7xsVt0QGmaIY+|;Rp!QWg)a)w>EE@{MgYmvO$OT2aGm8Lr5Fxu2@roCa#R$
fZ}D`lmTfn8WZ(Upc1cx1uPKI$jPp;lJ#Do_f#t+t3YRyxjtAP-U`$rpaVIR3j`v{4cWA4>2^TFE
B-#tzL?cjjzC$3IkSc-BAva_};bLr>*%s<ayX+$#EN{^0@_*R@jkaX>kQhQKO*NeLZ55=r>zn&AR
QRp%_Kn?Rw~PywHya0K`nGkC)xODFLqTz0uxdFsIN}NI*5|H~rZ$IRvYe!icQkoJZ*3hUsp_y=X6
(q00iy@_w}kiNQoT#uEyw5DakZ9%lOqAfp6m6tA(KxwsoOE>c}&g)T1qznsqoa^)~<Hp-VW`uclW
lo(am88FzdmyR~l&zzX&wiway-EyrjG`wlA9#vt?_PE+l0pk`AYD=YTf`)5%L)9x=7HoPPZnJYtG
!`38yqHKq?Q3fK|n2^^8_`r>JO?Glw9D~_)Whx?&#bj|EI3fjst9q8wEno`tCQl7bCcKVL-x7~{#
lW$aR;vdP)nCH(`K*RAb(yf&}zobM>H|50J@<NBC5r=lNmywVIqDqz!GtAP4wGEX5vmlU?H7SlCm
BXvlw)0+6porSrL_<);$mVRNv`Y9&xLMm);cQB)A#pICl{*(6;-I|dZk8r__=<E>+HjB|{{TS0r^
8UmVl?;`QQt%9r<AyiExTcpBS+(+j*cjlY*|#q9i@T?z{gO}+EBB`9<|Y^nVydHnoV`=J@TTb?SY
>x4|BqI{9d}iT2Zbsm&6iL+*H~jnot5I2y{&10%VLjN<Z1@tg1tJ*;UODYa1Xr3>!((5e=cPB|ZF
dOPckhyFuG!3Irc7SpxJn5^7=0@6gi`wZ15BM20`7rzUKj^+E!k95X->m{%W1>_d0VPJ)rx_7!F`
n~<omeDQn<N>ruVa>YSFE$jMT2TdLshRZ<gtTf{-8zX#0MyVuCi&_nsTvW<Ak)SY~4q8_jbumXsV
jZ`ey0fHs(Od_x8yvIownvv+SleiY8%@6@-4k)6to>caWAuKN7${^~2F-p~XndG6$n+Amt5!g4kK
_Sf#jTHL;rwb6vatk)D~SueB}WK97&e%GbQ?9k3Y(of>Wz|Q-K)hr-g&^r?QU42_bW%xK^QqV^3R
T~*A<OgSut#PNRbf5?-+Md)qS&UjEBc|cFoPh)y*MK6%-yjl`!&b=539#t5IW;Q1<p9MZg2sK;PK
IvFTi6*MWbjZkYs3AWELuYH6;n{Li-fWreYCkA>DG5`zr)3sGzThJ{_BLjXC<Xu@^`K}Z|NZ_aE>
6UW}(xeYa6Ww{QVp|5Vq+1@kpveYKXSmD&<p3YIIl&zht*VWc{cFP(oD?@nhhMe{5?41*Yr&i~sm
Egc|Pc+GT0gy`PFVb1Myg*r^Z=2oe%!)+1rfHgCiKgG8G1H%>cd&eOV4CB_EL=+nD2|Y*&3e`p2p
A;wxz29rH;2KJs2@~g<S}Im<_L7fU?>HkLcL>%#z*r-7~dpT+(s{x4o+E4*WXyb%UWko30zW8|L%
|Nq<ns8gWx1JNpk5bg!Q?24M@t-EL{7I=@ZgU5q-0YGBmnSZ{8!neEwdDxNn*$ISwgG(|o}k<rAa
Grnzc%5@TT)#dh)Lt&`K*nEZ)>n{bNAVQe<9_St4S`Ht0ZWhB*#eogJFN^mv|wp-Kcy~=`ObJdqY
*A^LRMO5FJS7n9bgrt;R#d%p(n2%7t6Q9%-q8O1-q?(pjRw>3?X*$C|Y1cr-T%Z|D<_E*-(&l2Vg
!q-^B|gxYeT3|K=I*7sA9H_Y>IjkLE8!+z&DFqzF<obb!!U<c#oXpCm3C!m<eE1m83s8KHDs0Vf3
G<E%ldxHQ#`As>D7{pvm+}_11)*Rv5m6TdgWk|ABsB|Ndh7s4eORM5YfgVO|}ZDFa~jwJmalO5i4
2S=2fJ*Sl5n=3C2Jm&X*w^yYE5969QI9W?9`rA^DV{T$9XN?xT-O$RcPdS2M^nt&&ekdY4p=KfX3
C+4pfZYiUV+)#y;q7IH6*I<~V;a&^Q2G)gQaz@2OqH@H^{hikQ3SIM%sMB#_r5UgsReWxX0SD5`Z
>bo#_#9Lbsi9$vKA}vJZ+=xg<Ke2%Yvm}tJgU`wVh+nItKNwNxfqLBOAntTF#?{xZwCv~jz-hx%z
t&la>tKL7==ZT}#;0|NL}cZ&Yn8?d1G2&J)u^)k)hdRe(~RhX`g&Z29oYsuXjTll(MHX7EQB0QeK
sdiDM>z*6bvKS2BwFml;TtkNq*clP%h~Jt!xrZSdFk@<ha0IFJo%#)mO%1-;@3vb8o+n4v?SmIYS
=ajKLf@l^#(1Q*mXs(Tu_aau`#p(<~@yqtJ|rRMM}C(+`bXQPQ;h5|Bg(8yE3`JTP#GtdNv4()=v
EipXu?SPg`6Bt5xK25GcuvCb?h^x5zPjUx1fZp<3#eBpSK7wwvkO~V7L(ILm?N3Ob2Gi_kbdAS2i
kZBOO&&?~AQABEKR3<2xFF0R?9uS6&nlCKy>ocJi{xL_bqLu6$@}R3V>Xbp+A}cXH4Eo*9uvV+bi
e-(_6$g_?<IDimGu7>EXqMc#63O*|%%I*eMGGyADdXyDg{`85)>^-cUu@0lu{)6dPMZAU6mMu#mk
Sf*GW(QSA(WWsh$u80CQ)NkP&iZ7GL}4M<f9_Y6GdwRe7u>ZSHSHC4Z-Enh~8kR++vP#hPT;af~x
wQvK~(2vExEPj|Xy}Jyg}+9gaCfhs~D=a3lck@0yeX<C#VnER?fTaC(Z_=X*{{!M1#8Wn0+m#3@M
T9IljouV(Sp9PN=mf$R@8C+#t%cF)*glCntgvSAsHiH>mh5<*dCoy=G+x8-#bb0A<@5^dX57}_dK
8F8fkD}JuX;0c`}w3;|k-5w`HW^tZl55V@#qDWcufyp-7fDD{BDZESov-0WnYNj|4^R--|PF8f2T
g>>;eU!u@&K1wSo7D_v3Bx1p2DFWyBY=6)@;02&Ga!~Z=9-x0Xg;>zqha5XdmF*!d5pJ{RzOnGqv
cB^MKQ-mK<J`teT?zJb6^TufT%Ix<{d|^pQjo0o5eS<{6N2x9OE6acAZ_K=c3+2!$pJ@^-+w%M6G
`H;pENf==|*O80}!c_vG;CGI?|McJ$`t;swTH?p-Ete|$4~@xuwli|#!><OlCRoV_{u@XP4+>D%u
we!y2x_{I6@i+68dy03Z%-(Dv0_2T6DYv}Cc)#=4A@c8iHGWp@hSFfP6pP!#yV972t|Ng`2#fQ^V
e0u)No9FLdQxl!y1vMiT4l#7}+1t|dZjX9|0hAt}ygvK>?dePB`4d_hOjvaB%lp&O+1sC>)JwjBD
IWiH`r-M>#n~H9>sLIN78zW{;~(F?c=rYdeSS{wXurOHcYbzp_U`TI{PjEPIoR(Ymcai9@c$wFf7
Db5@cl77KZNh!9$^3}c+mS6Lvx+}eDUFAB*R9(Y4g*ipC0|})6W6@Jf@#R`guY>NBH9(XWusQr`w
VLyYhce{@<7X59I&H^8ca47t=;kqpMXsn~WA|7UMn|p~}QW>1E9tunV1``UWRd+-_Of|GGR^hvG-
KsLH~##En>pFUoP)=)%fP%M{Iu;`@g+<>~#SN2=#`R3V1y8r>(BLpsiG5K{tg`iRX9(b}!6o<8L&
p5G|2Us0gL{yX^b{Nx<BWHmUs?0AM(;jcg6lVNyZ@{kvnX<25M1j>^+hTw0`pSL7U51Wo)pyiEpC
#3WuXj(zpF5@B~3AalaFp85nAB_SuM04%WS=T+gZpX=j1Ri|py@IK_D@RXZL;#BG>u6d1G8@gJ>)
gIF#i0}#>9L#_8^iR*!BUEG`J(U@-QDW916^<EUo=T`W$9D9F4(t^<m(&3d?NHQp&;96?IQ;vYux
Wr^*LIm+JS}5C}2U_)$?fi^T5lvUS-xZgEYi};OWOJBKpQg#hSR&(oBgBZL;Cze0e^&uR0or#gf>
@z}=0n<ytGaqJ4DKQ2&GmHz7#iKl-O4R{*RY?9=W(gkLW5G#U-{SJk<HCI4!X>>;01#l)ioGwKSy
Cs@#)J4fd6+IY(4`V}~2fw5utvcTlSHGLpojnAsI5yet@PkbOfdnUl)=G~<wXWN?ID|ToxqG!lgF
vnV2mZt)S9Rc4u=HfomZ5)>@j-HcAou@I5!0Nx1g`i3M?*w|cCDfn7q_Xu~Ml-D&iOurZU9K@$#k
9>wM=`W%n+M=#HN?`-uy_KWN>~1rZ?{`uyKcj~VJ5^x`<JRKP-x@XvpT&u^-!(&sw6T9nmHUJa00
>+1Ml#pS+1(}vUvL7@S&d)#{5-LQeZ--PQ}n@^8;*P>RqA}I+c<?0fZh!M`D0C{w*_c*EAkh4uyt
WvywGd6E=EI+c1p*)E$;_6rMU*8s1f(hBiTPC~(0%{J`_>*Pin<{JKpz<KXzj_61ZD*dk9N@VB4K
EC$R(3AuR4-60d{SK}AQT)=<FG*VL$cX!SgIbNO^cRD>!;=oEEW4;G1%SId!Z6uf8z*G?ilZ@Bq<
_a%F0K`o`Wg(Y?mw^a6qih0>R~_9r$V`f9S?^>f#k8zs;?#$JIg1jHMb&TUi^XL7j2FGvF@g)|Tg
Nsmzr41}!ZFgd)$4Rc4<(b;+~M(g3J+nQRs^BIO<@Yt+#A()8a!FTe~N0y9reG|0%I11*C+s_6+!
5Q`_Z$l90rzoW<jBjoH#C<RTn*@V%oaHM(yn)QWYFIc{$-;uPR1UD>J2L@r25|a#c#KMD2VWcOTE
z)m}Mhr)jm~&qU6;HHC*}2EcBPND;ifN@sdQ)1lxY8-}~$m&|4Ouk9v@-+#&sTm_!{uPh9w4bXkO
6|)UmH<hE@_&)^EHLf22tH@gH7=rR)H9B9T&#Z&d2&`85m?+H_T9+ew;{m;WpxQcfZRB#=GPPYxS
&fhz`VGY?RpTfk$cDSgYp8(1Id`4bZc{7vQE2a?Ek$u4yBF6q#+qz>6&oV;H?e{~cKh|<!%Z)U7I
Ys2`XE}7xYpeOzZ$~#r5Lt(33edD8_$n=GA#X;NO6fbfv4-MXhaN5iBGBGZG1-);<1U#X_SqJ(G7
D3XIqE!DzGsm^A&@>#hVPP;8$XwufmBkEHv>SKHuyNSRXK&3w=qf*0R4*+td_A_XufBQ=B+QOg|g
tR62lAK=rLE__f#FrZ-uEG`EmD60WS+?Y&VUzrs{d`{qafp!d=<R@TRiHJHl67*qf_^l-ThdByEU
YT5@pN-A_`bfL2GWyN!e2wQ$(SWgG&zTje%K})0eS@x8(QRyMy<&2gbjMqb6hAr7df+QqPhZVX(D
q+S|{Tdw(af$p3fRffSN8f6^rQ*fvR2HE0L{Z(4;rtsh{17YL`+$Lsg)P8LB8vOIHV!BQW_3B%LR
nD0GHI&PZHbQ;2s5vp;;QE%s^CGqIs$>FbidN5T=h{!W98c*VvPKo8Nb1B7T+WULERXPqjYcMXs9
qM)JW?;=~f=L{(V#3dOQAJ(|jz^*tW@$+Gu$S-P2Imzn)=K>N4@d1_$?e3fz{6_&v^B5BERt@;4r
1!rF9V&46wWM|x~D`p^Gkqep$1o<U1}c6!A-6JOPHODF4-9n@mjs;mlGnm6@5B~bL-Pt9>(FpIrT
qe?w0*iYvVLE8{n9Z;wGfYbG=54y^ON~)ArS$C>;5UDrNrH2gZ+4>~JEFCP6_<O_^$?wS{beZM8#
`qpDCICd<NI#dR>?j`fJj=FgpUF${NyRC>u7V<9?7>zMbzR3a-RmaJzBD*pN-#7tgFD)7aF20tz0
Uvi=)T=;bln=zeeV6Cm2;HUl{BK)__sjfwy~2j?&h&o3~fu71@#cU8ZjY4KqQWgVd{wADQV@<S?T
8&V*9}+BYhpG4jFE?wP<pP0`3K!TG+&g{Xr%~EZa6e{`1@C;wwPfI|?8`h8kkyp`$-6i(u{)w}CR
fExjn$W)zBYhp+()Iw6M`cZ&%?VY1QG8A&6`4WZeGFtJQwvBVEHXPp@>01)&yX_9^q1N)jTjD?Lp
=MiL4^vUESaT{a?kjGB}(C@=>K3g;7*m|s_wk$Ed<={UquV}NB5ABt$R#01Eh4_}t#)T3BNl8W@F
ODr6-4>j*8+aDOAn?sAAGz*ZG^Q>J)ZV(85jt8Zm*w{vc)y%m#L3e!(j0nF0wNEM;%Zt(J`Zgs8%
ve6zR?lhwK#Ao>btWjE;e}>Pm3W{JE8hqeZTq!r$kW8#Xh=&c5Zh5Qhza3)%szLS^CEv%T|j9K}`
CLL%f9gSX0TBZ+vAck#UmFq{(6#O2D-@)L(RTQ2Sxa*=0|yhN~P7>|SeI@yAN|Hp<gUs%u%Y<wLv
CR!K0ex|p=udsexidfp`=aKrjvm&HC??sH7G5Qafni2Q3=ky~0>Mj3tGR)b(=0n|gc{l>oqi;uRC
$Ixa*<D(iZ-XMpU8uQU*!;)Yqmy&f|Q<V+zHm$?9rIu#5=wI>B`&95zN89wZz6eWV%BSJ(Yg<Jzb
z9Y<%TCwUD9&i9x?1m6ZHGd_n-*ut%&_<P@Q>7lYE5P97kp(%W8+d9SQwdWH(*o(VouS7w?aW<kS
*p7I`^kX!%aubMukujA8#k%$<ATGSL#!?Erl(1mX*adwMpjLnNDt_g<l2((=+ZA%dl@pfKxRwwCQ
d|RKJrdmZGvkr7dE~Xv45kSx|K<_(EE@*VwwVI-IVzjaK<$BnI6KI{gC*yvjzKJM8Ulbvp<Bqc3Z
xSKZE0zuViTp&FTT<L;Gs#ekDmtRv@2285Fl>bs6B52s2-!qj<Y@f~&d?nV1W*$OkJf`4fpn@TmT
pnrfmHMX%nf6k$4pWgMOE%>vd{IiXFle|$PHgDac0nwCpGf{RLd|DhTTj&F`n**Qqq@bx*i#re*`
$lE6uc-^y*4DE1_x6?0ga*y*H&w~U(}JaQTKKD~@aEV8eY>^es`~w{tWD``qVwpFFg7v}xo^fWu;
`P7A?G;py`q*kQnC_^9&W}`Yut?;p$;t?ubMhWn9ysM=Kc~rduHDNRRNPKZ9gD+MCR^J4wU*j%mz
r~-Ca)KWw%+n;_K)~-GAfgdOMA-w_$X>KYMf=4>s3@#4IA(N+0s2LE+~!z*oa9!$VQc@g3n>AZqv
OjH~O+Uual3l0u2_ugOqu!)m|3TQ)qJ(;VGrJkg08YN`DO-HtZCWP(n^n>M)!OJCGDp(KxP2LWNj
P<V=8)OW#-?X=tc>-Wws#c|urzi6M#HxWC14miiDOE;g{s?skN^{6G}t=X?hl&R<qS;IIQe-q5wb
-YDM<tt?Daqn<|3W%PSdf9$>Ry820djG%y%21NluA+5H2`=$sVC$jz(M(&ax4r;oGMSHGw8lHnKy
>BXW{@q%>ex}ox9ap<&X}L7co(9F4BE%-<(QxTxP_0d;AIg}hh_o;n9Xpv`h?-zSyvlOyO;jB1EX
62e+%Vd*u*=+=3jx!7r<n9c*I*^u>+sLV4~5robC4i3BYZ#`nBY$-KcMs^yb#wD)DbnBm609Grnu
x_3){h&}P})Q)uhLoAjs}8E9k=m9Nd-a?4@Cu2TiGTKxZG${$;o^RyQAi6J;vt<A8)J6<gKtWrnw
C3-74qR>?=lo*e-XH%U%2y0hF5G$cTt91DW%;?7ZzS3~nCPJU3wqb*!xV~8h@M{#e)#PWpuC}JRz
pC!zjqO>Us#SH%;cyq_+e)tl#q2lms~)DS<TiqncP;E*&FV{Y3cJC<aI&g+JH@U1pnsiN<oSBhhv
7ejYQySSz)^w<_iM5xt=N2%>ODDLE!ir-x$G?wlH#trVyflxd>&0;zA~~pS4U`2W;>}ld^QEy#c+
-U=lj#64LelkxcMyFtc?q=GCYVY6yWq*&!LYY@D7FzTN~a~8A+FR82gHev}BY|k4<M!4cs^S!=S&
EuF}$zMPq(>_6!k`^bGpRLsh?Y9un#)(P=nq=c&y5;7g}S>v&M(!DJTbah-vJgaxp+#!d!nPUWhd
<W|9hYtDh}c%Drt<)^M*<pVLM>1(5!hl*6oMQ?+CGAvaa$t05sOIK~pQ+it%9<}IQMP1wUqMmwLW
T?Cos?L_<<1ND4W{(5AS=;eor&fJWg&JF|3e8KIlc17xDCDWm^0im?pLVUcIKWL|RK}K0SzuyP6>
~W5+;=<h&rQ6^W_P}6V%ArIXV*xcBn`C)V@&*wsZz+9*tWFO+3C3jYvlf1lT-?s3Fc`Y&Lp%RQE<
A4Y*MEbQjUr@v>hFp3PN!)8pKqkxV^2}(v2u{&;iAJYjPhAJGNzEPSz-*{+M~YeS0=~50CXQ+Kx@
AQ`<`uyK&_Lb`x@(RQ&ZjvX&2RyDc5TUsd3$3><@?(h6AKL3km-Zr=+`X-8ql?ozWdGI$MX$C;@H
(5`orZ5(MCo7!fQQj*_tEVyNSGvW}XRz$cD@lBB|&CQOK>LltvgtJt=I91uFXcpxur`&k;UWLm!2
Z8&rN-~|D^7$;H1OdUXzh245Rtv38Z#Xk_tF>6?)0E=xnc=`wj4}A@uZ=c`l*6Dn7@)6+6^8>!F&
dE`jikWKrtw08t98F^U18b+=s8|=y1)K<nZO5O)Ud$*6J3BX>(^h|B)_$YmKbM|=A+(I&Uem|NqP
JvB+vXZp;RN33-s4t4bZR^&Tujhk(*vCN%_~}z;~GC`#Z`m8!c}n!amOXGAT0fUZWjtOk|3Zkl?5
(4@*LiF@7rU5X{RorF<pn@)JjZqrlD->8?%S#;2-%eRWT75msNbL3I1$90U5_=N##i)=ejoqG*W}
I5AZJSb?06k@VD?m}A^8fZIhY<9WnU0x@SO<{C6Jk)?p`mqwYSR=dS0shm(HL!0Nxngh0STtJFjO
{*GyiV|*?k_YJMu3u-cc2G&jYsJ6{lEDShK1w729uaq7Ztw<;3dOl>KAPZ<S$LyQ8iS2j^*GpSae
u{*XtfXxQMAi28QpjqWAbI$2n=%DDtgdr0f%w92fqlLq`(kg;0i)xH_?Q?CTR<nNq>aZ;g5JqV}`
z=9ltN0Q}{v(s;j?%usJnfFra~a%+{Gz<!Z6MObEVM9s@jQN?!d$iRCzv=7q*O3Y)kB;4C@pBJH+
Sf<cTxxajalPOy!*8>yhv?(BCCj?|p&;4wV>R~Th8RNeN`zQVj=H!Cuvr`12yO~69WI503J;>Nh<
upsF6(t)M>;pFwZ(T{J>F3v~qPd|*_ppzS3qIIA*^+@fvp+_G1-^d&1ibw;H|8&U++Qf~hX%TIDg
lt>=h=C?`D!pqM0~y5QPJ>=wp1ykb;mzpzySJwlcTb<{L{8Kqn%%}32OQ@o*&<G&(u1!3B#BT5P<
)?K^2?^%@=T3q;cYygIgQQKY5|l9@W_1%qmN1tac`B{T~@ZctZa8#)$X#o-5HX{o2fg3aR?;98z^
N>^v6`HyDZgR7Im$YozfZVGZ@nvk}G!B#*YL2p-q|WD4ilklYXeW{UM(0{DAzLr6fy6I^CDa)%BY
d0o%!hNXdEP8<TN>wz>U{qP+IG)J-(0$o>E|uI{l6ic47KBln}f>ckq@qQu*#=@k66=zHlQN3^5-
j&>k2PVGTJp>l3WsXK|TOc0WZHVHa3H~xt8;!lztl@e^y;CvM#!)<`g4to9J(CM1u4|swBKc^s?j
!KoseXJyxCj+XoFM;B)?0V~T(B0etgTAH%dig~il!Q>fn0EB1E()ZE;|?=2;X!30I!ff@0j$VShj
Z3tikcLbc9e~yqzJtU<i4FQvi9AaFS{{yLb_a|4^|Fmc^0fPu?j6R;>qTskoY4!DkRSU=Mp3RcIM
<l=5y(UDsa|e3`!o2DZ*fA_%>9SFh2uQ{t{1U8f%q&L%Gc`z3le%TmnYDZRrHTStA$Sp2b%{*WxH
^qr@Qdn8nGbW6oWIeq1KqqQrRb+aY4`Nt-7_xd7=nzLvzdMZ|nvL<SK~CQf=&tiUB$0YP@icGIrA
uT!*?vA$YG6<<5+L(GuXPMdBe5>91m7u?z~!jf{w+~;jxFUd8CJfRG~jUWxI?kt&_V4)K%l#A%B-
&m?ZK4LvaaQK8ds)?l=y)+fz+y=+CzLfzy{qW}G;>QoCrOhrwv1&O()cM>0oIK-(S<dvF4X?`_Xp
t|*-Dan>zvOh{j8<{tGRvepDAGohwFtDm>eJKI=55$5VIER2Qb4$^;Gl$d6;s>1kKH_YUy>lgPMS
f<B540}F{6lBCH^KYk_{AN=Ya3#WE?mVPj~^2-9!hHmxi)F{bnU2!;}tQQ9t>QK$t}`E<#J4Npl4
LQsSZVuBGsD^(zcbz<IEkh2sc%c!cwUqFJ=?k^*=ujjfiWSz*Fqo&1I;*QEY+TZ|76(18^b1{6!f
veh)ajg%IBZP`hu6u=G|oN-~(s+c5;f=N`bASo>5P|714VXsg`h$Ky`IX5)H(b)vvg8Tv?KtN;oN
6L|%NRuGerlTngYlMO0Bao{Wk~R+&2bl=Nm}x+_W~J&wNj$ud$P0OG{A@#RKzL19_Pb@8lgeY>E}
iR`|AR*o;3<ofJLWx8WODiiVFVMs3zrk?ncfLYP8mF~iE0Ir^}*wxRdT#ANQXr>VosyGrEwlaE!B
Q=dj11&U^Yhaq=5=P$Rv5PgFCxqZ(~-Lw+EpptZtr}gdDg?JY#$wQ_g3dkORlelauUjK=AN;k?=_
HkP8)vh@Fl2VZeVlEvuz<BoaWc%8X8t08o;4=s`SljCD1FFf?In<B>fA`8F^)>tCLppT0hQaZyTn
?yXE|Btpx~DoNwGgS=}Wn|Zj6qq`Ahk~C}s4&@d%A9pe63~MJqOJucN;MGoj7;FTtYf|ozpSKhCs
wTn4eonJ2y)^5KWs3E6sDaJ#Xby8UjX>bdJ?`1ow4x>q^SiN1CF8@;N%i(!p%+9J@iP`CJ&K84a7
Ha%BSmU`<`&jK5$uZiGE=R4e)}2Tw$*uB&@Lop&^osl+&9%4Lp!L}GZlQMzzu6ouMAu;2<+%$m|F
TFzVXh}6mu=JdS#ZTI&rAYj@Y;a9N#j&AAxK(n{a~c%2(|(%<&ZGYZLfI(w^HD3Kni2N^0#vfIB(
52aIXM9EvaZ_LntpbAF(=fT00Hcb|q{rX@xTO{nhJs1&af38sS{XD?*{W7DCPTZu7)>?`j#m&dU0
)VL&j!397Sm4jmH8&#z^Yp6%m0T*hjZq(9t81r~Cx+m*o95BY<rOxe+AM)U;-eJSNcBg1+T{P9*&
{TIzQ^jI53qX917lE@bO<mVo46~*<5P@h1?c-^p4FC{9uBqf*SHD{q?`m$wi}le<VX9at*<LL$S6
|@rLYNXg&w0l@Xm_veZ9|ICfEV;Zd;hw0u2~q)sa<zj^QMff@#l#!EmD)RQJjcva5lj)aDxskS)j
!?|2C9#vPK0<<OH>#IFESNz@^nS712;fbkVJ&V(#|>JE%FUCX;N^0=qIHK5A>>-PZ4xf=+Qi15;s
0xd`yvlzeqlfF~tK3>r;t7RT>Acf}^%WS>%Dt4VxKc_5JC!}cfU8ljJAheVNb<>dR_eX4)<984${
Zn8M;Xcy>32kAl*V9{evNGc1f^|Z5;eGM_KX^ZvWyfxUrD*Fd&46#t#JXyhkII)=?Dfkpg*SBRJi
F=pU8*SS@loen?VLR<klSp$HKX|n!X&%rxkQA9dJ$RTpgu+13czWMRKaHYu4KLg?E?1xz62<oG*$
Oj*WXC;k*9ctI9c^;Fh6`^(OgH9S5T**)n%PX$KOmB6J_#=f4QucmF$l(+TdiTnwM-w>c+EG9T6l
ju(Jf-`Dfd1Y7DZ@dmh$~5plzl!3LtHxNJx`n$78r9#uU6B&M_7Y-rr%GG%H7WBDaal^e*FTy&GW
RvLf+34?B}BvRow<Ooc@#YRHmwMsb^t)eMFm=tA-iuc#M9Y7z=2Ws_b$Sw>u>okVw(XZx5qc}GJ?
9hm&X+ZY@Fz$=tn1y5s6JUdqs;o-5g{~yJ{XN6xH(<L5=x+FFQF0qi)ahIJe@``sZ>Nz({<Xl6w&
5EstpECMWv_77N^Q%cnwl9794aan2&@Xnx&`zUsMq)T%D3J!bw@a@v8$lFe+%2Y&lN7dgh-26IlC
9=*M0UW;u9Zzkzee_uXV9fvMI;d#48$cJzzL7J2WYOv8>0&*09ymKO>VdoZFD2wP#MdelMvZ$cU)
S}qbU{k=se>f>86M6a54!7vif}8V;XqG145Da!|D6iCofJdgI*iS7U7b;w)I}A<<q(3DCYIBYPj4
wy+@qWoKXs=UrhEzPNVYJ+D{-E=`nz;j{1OOTZQYjCsJQ&<ji&vyTbYc<hv$(OU%hD%Ul)8*0gsU
e=5@iY?D}?$$=2vlVa*4?2MXY!PZwXi4&U_Q6Lpo9EddYkWvU^j&QoyPSaUCx_7xKP4o)RU>j>O)
W;r)GryU7eP$bEwTW@q)|9YqGs-0fW4PS=?yIl9Qa_xYygdD&;3I2gj(VLAf1=kvoqjk!d-t|@|H
OLv_T9_VbADxMa|!*MW++jz0$ClI@rpq?dFM3x6PV-znWo8a+Dzm%Hz~#G_PAx;0Zuu<m&a~d)Bz
cY<1+lvv=-=E9xanNb(9_iGOcSRF#?eILHqD}^DoA5FKm}yKuZrS>M+b{+7uu#-ACz|{;uWkXODv
8RIm{JUCZCk^7qatf@#Gc7E2Dh`1Hfs$!mA%<~a2@oQ({YqEmBQKNjwteW%S+20yu6(Dw%uzG=X<
t21r3aD@D@9USq99ghf$WsM=y>Os+0p_g>m=R2)hbZ1lx4nXmXvlkX3e+kP#hkyauZ}gQ>x6kj2Z
BAc(#=_xee%Gq%|9o>!*M-b{B|u|@=8$9tn}3PtDUVR}-DE&xu6oT@)7A@Lc2Fcp&t`-KTmbgQ{{
4Q?C|DdWvMb9p{8t$)J%j&HL5bJ0wyKQEl(z>ilX6dKzpBhD{_MC|@kwrTaY4YVdnd{q3l9eThJF
t>yTm$ZA>$J67j~M}4!*a#Xf!u9yNqb=Y+5kr_lBj5E<GQQqp_wrVBw4>1U%u;k3@;*v@VZ1VR|)
fnL8?y`t(z1a?l;x*Iv?ChYyYpkV1LV<tN<+ve`v-tF3MY?<cK+Xeh0e7(I__bhc6Si9_|Ph&$nG
TPw?uAoGXMO^sal=F{4I@`<{C`gP2a*D-R9q-5JtvukR0x75_oGOVfwnmn)<iuC*yD&O|%mhS+x^
54yKj&D2^Sy32tx;7w}4QFFQb8cz>6n0l)b&J470ip%%w%7KEE3AV2#cy}$pVA*J4!v|<T)^4+_W
RcroX;Yit#A0sy#yV3mpM1~>B7js^1h7^fw7;^wO1)sJXOK%w!i%@8U_TCQ4%ekL||4ct#WM5@}^
+4pOo2kw)DZ42K>7-9O~nYkN4di*h}|XrG|MH|K8TgM9%HOVHhm-0&(E<?Mq($MxEWnoo6=@X5%=
fXXvPaH^IUI*4a|<gEm=~L${Y`h|GKq4G7iv^3+js^PM%_&C0!M6IT!pd%UXM^@euKKZ?*?cY6N`
P3g^IWI&YI&^y;y*rk+wIb$=&EbuI4_~k$hMTb>ZGHg+f8m<IMF<amR_jFD6|5g4;JtK=1_I~mxz
8MwPYPJcVKaz&FniWm^v2Sx_HRaApmnh8zmU^1bCTMM6h~K!-HGP+7#O?6q<bx&SvMZ(=uCb8OtA
x2CAUImx*Mb7gT8G8#uxx2oC65rcRqJb8CfkI7>;(*)t*r#GQZXRbogSCWy^2wZQOnQ;J3XzyAA>
Ih+cIePje;j@W8TUM%*X1C?0JEQAq$^T`l&DjWdY#A^}-<DAB}rj#v23gpN(Tjq^;9(BpWvw#%Jm
4wnBx`@c}Zd=R<p-t2AZz0c`+;m&74yr0>`Zg?vR+HceN+YhP(Of*u}Q#t?<|7VAq8@FkFiS7fXe
I3`%Jm~yjqI7z|q*D1o5&Qhq+#@oJS;GT(qwlE|%D5rk>Y~noNz#gN=l3UqciCdbiOUrGXXG%7I1
|I`_4M(6ebkZ)$ivdr0SfC`Er&pT7)dSNQVEBerWq4P>k_N=j^>{3BW+MR?PnCU$aINVwKpW|0dP
cTpSnMd+6bp)w83o<oqa_7hk%Y;bH%*qOiv@mwVWxM$vmHEEb7Szp?ajsM32$cEO9`zS2pfSU&^L
@en7O`9YK49#Nrb1HZB9I!i8(-cA6S+M>k6wPPeiRSMXEjB;EW1av-}u%$cA_M2}7eHBS8@;lQW!
*>?r}kXT>yiM|e>}`UmYEoPtd<eIe@O%$-u;pz$6qe^a;Z2e~!)BOe~xh(rt99Xj?tV!2agK2?x2
#x7FOQ1=z4mDJEyrq#9L;Yv+%VX_li;9Z`6=iMt68>?g-$u)}oCwBre#W<0AeSh}0p%vS&>lVnZY
*b~|Tc-5D0n#2B$>_u-tx+;8%);Af6lNo2chIu1FfS~+b2vV%Fwu0#DN`mZ8z!6KJ}9P<EoL!lxX
bKfg(Yp7tTY-9g+K#C0}}S?@NmJ>$NNiL&rfcJ`Gc%Yy#Zu!e!iV;!IF?Ci+_0hL1VsZ)Ts!~V0f
s_#dbC4b1z@~SqOmHnE>V+R7V*hOxp#n1TqcRiX}o97oHb_ie0N<OU~9KGKm>UvjD_b&wn1Bzc_h
~AueB6xN8{!j(uQ$vu~oB#z^(|Miu?k;*dLB$C#kQB1VkqEfK*-Bes1V(H0zyjK>0ctO3K82P}!8
JNNJZF9td{2>
