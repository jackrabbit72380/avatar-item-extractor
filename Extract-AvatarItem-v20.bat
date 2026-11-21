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
    # Straight into the item's folder, so everything it makes sits together.
    target = out
    print("")
    print("   Rigging every item onto the Halo skeleton and first-person arms...")
    result = subprocess.run([blender, "-b", "--factory-startup", "--python",
                             os.path.join(cache, "rig_items.py"), "--",
                             "--items", out, "--rig", blends[0],
                             "--fp", blends[1], "--out", target],
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
c-ri}3wzr((kT2_xXza?Sxbs8zD135j*~d8-_7ky+-|$Jk4j6l%|;@%qGVg?_WkYO+yDX~C@D#Ip
L3q?q^>QIzyKHw27|#|e&333<9R$AOp@ZJHC=A?w;ufE(W00=x=gc2Np>4dm-CxE>z!xkTln9LWS
EbVfNKR4_&hFxd@&F5tKf(p9u-A0e-{rww&wXTNV9n!ynXgxEdY?6-lRnUKl7U;n50FKX4k<u%{~
TK`HUX+UIe#ka@VIXQ-Bc^^L&;RK@tydf*2vg?;t+UehE&$fB)#i>HBBFFwf?3nkBQ~?j|pi;5Bw
CxE$wDJxoVIFTytCV0Z(iu%EB~@pE&SPo@C4NJi%w6)l3Bd_2M)#ldAdZ({4oC?LE9Z}RyKzPd?f
3ADEukAll2xLy!|;C#_-cXonw4&xY)^E(>gc?N@;#PcAXOvlM2$>vb<aw$j(jux{x2#2$Ho)nK5n
@z4zGyqbOjIW?0(|m@QJ<slwERDY@f{)28OU94x<B3!%qDF9+&Tj}~FtA`m6Ep+F2jfroFr|d~0R
G8L2KI~xO&V(O#4~$O;Uy#ebv#a<<s&SeU;Y+M;A;y$An50Lc9qU1FuM2}5M0cuE5%JZox(GO-8V
W0qr=xUappu#VJP@A&R{}xYs)klkBXqv>Fo!%$!wkuffgPG-R|B_FrTGyc0Gm%;mc&AYIM52E|%E
Y-HB-A@A4v@r+HSuyiF1!RY1+NlQ%Dd0y>v8f-GmE0$PLCahk8v>%}bTm!qB}aRE<?^Q_a_e;mZ)
97^2>;bIEt@3eM1@@Uxz+AZiSfBQtk2`=N02o%WUI=zMN=2-&Nlg)wjCzt0LkN}VsU?t9w^q{#`a
0)15ybR;nEQLzbWY$CsB=_(l0jMc-6|sRW+$HJt4H8a~pJ#|(jjI^wb($AUdNeN|lW{W7vmm4?;6
`?%00?z7i|>MYI!RgqQo-bMOsnBM(|D0pkNr)6Sd$=25||zha~nRUSq4RcC~s0&vas+Fy~Y|i&#?
A)wB%#y8?ljKo{wTcU~*4Xe>KY|)?yJ<CWxsyP3_-j>3p7K!EHQVlw+0I#^Q=ZG_vw+yu{TE>uk&
w#_=36b)Lz3$7(<R#P4omScF&O9M&Y_AD%<;Wio@#Lp31rn6Sb~$dVNC(o&2PI|#$Zp~SOmB5(cR
w<0g!=7s)P%x8<?y!^T>3@EUg@!N-!@82Aq{`mfQ@Zsbi$H8IHzVGa`&$DN*-ah}^;D_U*7sv0_t
4<e?1eE^v?`7eGcDs#mxcr-=*T)~=`R~jk+Wp{s>m&n&rla$%20!fJ!z1WMjF{DryZHDtxu3(r&<
}g~kk+++w1ba6+{Dx5Es*6b1s<T^?b16TAN_QX8brSHI+@2KAb}q<s9HelN!hJ^EcJW=8^q*!KF(
*SF)R%I_MigeCkw(Kh=cQNI0pWP>l}G+G769HhshL&8TEx}!h0_I0C?Zm{lk3)=QxQcW!ulv`3HI
=4Knq-`tYm?Tosrp)`8c^(sMuptm8THN!~?eMas?rJoXAULSQwmk_ZtfJP!tgG)w1$L5O=xBS4g>
LE=Ar+QNrG4fw}-lV4roJ^&QtyeQI7$pAW8z&l_}A;As44Gzq<hd0Uaqcof?CRE;RJiW47+17=Er
%o$ICHyywQ{3_O{GD$hz7SEfMTSi6;V1~V;TLTC4@c4YR`4(gji$=(G@OQ_$Q%I9!0P@RJ>J_{+e
?H8`}RmNe%Q~j^7&TepqDYH+brM0ZnPM?6LOPYIgj+b8G|n0juR@cz?Uz8djs2~*H3{f*u#OMKuZ
IpM5rt+Jj59{OU;p2AA+2hg$F^?tkfXDkzITe7ayT`*a@CIp}G-N>eyw7(W|i_p`A(NPoD<83;b=
g;!FXf>tE0Uwe(j87GZ0IHoG`ua{G{aV!tA!G<|Or^}6pY()M9{mH-pYq>nDy4HgGfT#=tkcQ8Q*
Yw2xq5V$0FP^CEO2lbaIK8vco>FiNY%x+Zbb@n_Jd)@UFd);cq)Kl?RQ9)VDfq4t$!^8w{5mC1==
klNv1#oNuF{#?t-cBvD?KZQ>nFf>`$~M9b$v29enYl&Ep#oX8$Cch(tw0%x3atgnEil1Pu3%eJPt
~&%dS;?2iq6^>W;^ldHqM5LZ@eb|iR!7@f;LXCv%x$cWFQyNDy;P1-c3TA?e9l`!2jO&_Msj9Y5Q
=IfM7TVPCqNkjrgZz2xrX?`jx#OvzXZY=OWJL@OFg7LD;#B3luuxl-q#A;eC9aXYm-OA(=KvWRLG
b0>&)~7T)}(Sidc^cu+wYwL6%Bz`4MUmP@rXk+{=?-5T6)T5!2(!B3kMgu%cG8G7rsulU$reU;_s
SNXJQ6_82iF?Xth(QkuptL-hntSKKt1vqE+T5S||!aex*?YD6F+x0j5sSZrftmu_Dsub~n&WCbx2
?z~*U|D1ZtiNQ`*XJPKfMI3*6B<LZgg+liVPJy$CmxC0tycGc5t%kSt>6OyYQiE;_~iFb*bx&r!v
qP4R!h=~1ff12593K<!ox#09h7mqA;uUN%gH2x^B8J`pdT?wWZTVlYroTpz6<hck~KvQGEOhQDNJ
yqd{{hs`S$(mqtg$q$q10%!?QZb!6XCYCbt;#0TBf--K|T&%t+}J3~;E3z(GM}SiK-gE4%^Pr?Y&
t7&7DuoJHf|e2gj-Rox-#(53lE%d+M|pxwqGu;pqfOCOYF1<I$@P(Jyfe5yc!$ttN__`$Zl1ilTH
cKJ_M`A>HFPf-4owK*<<t9P88kil%D#AmJ~6OP^Hz18Nu-R3=1y|>y7snIC-3$*ZwK6*NEj~#%uX
E%Ib*=<8A++bYspHGo_g8T`E$(p_68SW7*x=zOnR5V?s_sOV9YptX`YJ1ZSq7lfMh3X!@jA2qMn}
#J))A7L;spY^!tse>~58HRB%sGcpF&@gwa*7nW=thSm##y;p^ClX^mvFv=`Xst;$TA7JzU4w7Bd2
%n61mlq3gKg$!J(|8@mw9KAl4BJbp=|JaA3Zk--J=UtXNLuwmEgC$oQv-L`oly8Xou$5sG}0ABLu
~fGPC3Ql@vhO_cMRH>9J00i&*$HR}B!EY<A1YCzKC4|vXwv}*bY2Nb8{U^vcE5@dy7G0&$3v2<45
BPz#9j5<_UL&;q*2bv)zB`HNnG05=ftb;n;jC277No?H1@2FTnt)-~DWIc6}^R0w5oQ}szVcjx^&
7X%ii|ixHVP_Zo02?UJ-L9^L57S!6t!nC?7^)M42oQN5v@sc%(*FQer6lg3kid^%8q!=;(F6d)t8
~C3UThWCXQ|6+N>ztE@z9gc1sBdc|9UQoK`Z@>c>ofIbqFO515BW?q_~Y%3^SFD!mtJ}k;#=9Pm}
mQ#E-f(pkEjFp$0+ABrb3Uk+9;~EMA626?cA7m0dSiK(-YOZ8Q^93w3Ir?pw}E6s<>JQxv|vC>w1
AhSE2(cF{BGVZVxx3uufQU5yvvJhb9)Tm17*Wq2W>cn=Wx<$$?Jc)7T`N@h0uIVLfb3iN>)%u)A?
+$c<e(InY?wq$uneWBUI6`sk};&PnFqw+jPGy`qolv8v3DCM4<^>+X}@alZ)m(%axpKsYJ7+fk?E
DD|kwt9Z;7FXP$YM+6c<jY;5wjGEUx@Tsy-JJl4Q1|sO)K@~N+1G0OboUk5*Qmz6dJ`7|I@9Cbjp
`7?7up}E^Z7U#;4vZ2REb@)L^?9K*5z5ZYw%3_O;6rbTI}v!;DGJk&?eo{*f1&`S{h4_ikO&BSpn
z<q>J2<C+L01TEeRSg<rt(DZ$_#j_Qlhexz|p+m9MCLsz)jHn3rQcKHog>a}Z-(N$;Oe1=-SLs%<
3J?C3QFV<914OEw3EBZ&EW*;|0BUfRDTSX*uQMFAv8=={nY=K12=IR;^@K*8=?Fd@9&kdOI5Lviv
P_T)d5D{RkC*+z6^YxHQ5EYo_ta#v;Os3j^qgeJeXF~Ti-No~X+k6SvyOSBnEnm;`c|4X29tQrc(
f6{P@JF@&TtpL?iwX~vT6E^3BI_?}h=f?pP_Q^)vms;a(%V1NM57#p$>bZV?~xZPyn=Mi$lBAOkw
0xSBSBK_W_Xc|T2Z=74$aFW-hWPxkB@`>UAzOz;@PsZ7c`&p#dAZO#&q_Ys7L(qCxmvJI9nHt3MQ
+GM`@T0x`+C!T=oj1RQfHvUeB1fhJ0W3H0ZP=D&Bd?WhSWPEDAg@X;8hFFEyJeVK_WObko?IZ%Zh
oT|+Hbv%BMm0WH^pVWgdJrP&pb1XeA(2UU4^s!$eZnr>_`q-NMI>pp@}cXwFnAl(afpMY=gieRIa
@pHcF9`M2n`Hy?n<Vks(C4m%Y((DJl9vzbuyA1D>EHB^?Gaud{$)kw{-VHCuAg16sXPVx_!1Mu$>
bCpAIKK<_cv6rk=)P9$j6%R-H+b>$X{SLp0r+t@Y6Lgw^$l<kRY$0RHvyzlJeeK_2hB8VcJ^RAck
z^9^O*`*I;;GI{_cSHL}Z|X)+&q6o)`|?caFO4MzH90`IOEdZ^$r(KgVNO>@izG(G@m6<VIi&vv`
uwBN3_bdmthl7Q7nA*9B25q9K_~=gXiN=kv&E=zw-0&zbFNf+WxAKWkqIO<UM7U&E@9p~-N#g%xK
nJbEdj*bx#O&@I3~Mn`{O;53#-Fj#evv*C5r1s4w-mSvugL&nKpNybpSTtJeav8AJg$F+#8RBzaB
i1jJiNJiJUcT73|&>pF^CI_%yG?d6*YQLXvF)@PFi3o4N3{V^RUGR9m#ckmuHEU3fP(#%iN%qchz
NMSQG6qi1w`g$qls?cCnofE|pYR!(G{6)5`$xI52ea$T-M!uLRxMx@o5EXSiXEFNUh6lzkwrZyso
z>fm5dn9=(;fq{uRJSsM!T_4X^QGmmXf@!ySBhS(d!yk_P`_O~hbyKM(nEZ_y;|g!l7ZUb%;-vr=
3Yi%sANLHO)B3<tInWD58VnwsaR9|-}@9a3zt0Kw%Tpwn&x%`)NO%f@kYklIGpej_GH*<vzXqMjw
2TJ(mUtn%}0+QPM2gdrZwJF5FIdil<}xCS8v3R8a+fsqgh4{?d`2~AKjnlGoxp;H{sZGa6+d_@58
8>qNIW2CSNEq0@`ek17jo1F{exd36|<PbO?!b2SMUL$r6mw>fPRC<QIjJ9$59z6<nU^azW=trh7T
%rMLe~ZO0@A$80+-O^d%MeRYaq5(H1cWi+2@p$G#tYD3b3v|~!T;eI$xXTg1iYz%7>!><rDo%DiA
s!FoLwi-V^cV%xA(@|yNZte>WbtHyh4C6Y(w$L9)#BTj6d@HoRM~dG!s<pqM~)enegbFV%UD-4$I
#mfCDZLLsDNl7g4o}m@PR1yZnYq-Tnc>D34Jd81Z;|gPih=+rOxmz{6=fcnU8)y)Hq3bb1zs`!FF
X;wVOGCB+XNqM?04cUoc_$ag>TG>0_0K|{NB4efdw+Kn!t&>4)dySwXYbC~0)0#SC*@9a4RYC5D4
_Xb3++No);YO4*?W4|A^W&WWM&OfqK^%W=pdF+8Rhr^ChrE6E|`KzR(`#P$@T03i~W(sJWVykNN8
MdLg{?c)a$Kzy9mR4tH-%e!;8UcLn@Mr%DL1sThvK#uyPJpU2)mex~%xU}VBhK@*1AmDYdPEB!OI
qkLAz-u722d45g8n5?YiOsop|X+g*L5B6EI)2(1Uof&;!fo0AQie_Q-~Nm%<B}{;|})z-d_mL5(y
H$bn+}j3Irj6W-W_Q9O+&7tCD667n)dN<7%tvirLZ`eSjs@;771})Tb_dB9LeL{22ChKlU$bI)cj
QOFdAKFfQ-)s8RJyz}@5cSzn1becEI%d@_+Nz%P@G9+5x<qR{*ApB<@_$qY_e@zos8Y4C~tD{${7
aYrA?&<3M*2?wv)B16k^ysiRy;T?HdG}MKXItET-5D|uPhI6ne5;opNQHz0zc{AT_ekX6C*-0`-l
L<cU6(sTU6p>m0KY5Ni?uo?_uWadS1Hp~)%Tms_3hcM~kW&@5rg1tetlJa1NpcDR|L%7$L>qP1!7
px!j#;8@m#|JKRQ%s1w{0MV@l9Dp3N!4fQJ$f$8d4Y4iv0IYwdnrO$z&`;svD=T6UtDsLvDh9eL|
976vNUeg#BL`Y*QHwF}Ar3Rxf3(md?tyYGg2$zfhK9(W_SSVyR0N>|JauZz)OZ-y&#DaXv!8b0Z=
U>dT)XYRwnZaT0DWZ$-NCXj9l5OI@|FHxs*@=2psHpEHcG6uzP_5xz)4R*D*4Zm<lV9#*wpD{K%n
Q_PVmB6QYleYxm|L~RH`wes6Nc9j}iA-LhSNt!K^|D&YL@XMvlsD``Jy#~(Fc0k+OPQ5f5&-*d%^
?0{0do#5itu%B%*;8EwFgwBx(PJTHUIK`NbZppEX(N~}8Zg+`0}ZxR*z6AA%hmrGbc413r1Y=V^D
jV>QVM=szE=13j%J^=`sgz0(|n5-ADT7Q`0A3Jq#g1kX7AaU6#4|xBkDThSFcx<UdtVfuK-w<tho
SCFTYIv&qt6yOZm^xwCX>-3beu>cN|=2EF{Vo>7slqHU01aM^1jY8Pf@qNVE!BOneF@fY@FSd53~
(o1t)FoB>^673}i5V8h!1_fnyv;dieKD)$L^g+QIeXGWJRH9<Pyivst2$rUOmOd=}w!j*%jA|^P2
M8;JEoZeu&RM&{1{A~n_MsV8*hGTeb+wn4;zk%~Wf==~x*bCkh>R=54lemVJ7K!P82dx4K#lfAja
>9j$9GRAxW+U7Zo`(4&g>NX(P#?jV=J|Is*pSogn!_<5Yx)L&Et5++6~hNv{uz33FMtrSLH0xdmc
Y=P@o1zBK<Ua!U?RwLMqYpDnLkYvgFP{{979K7%fp)_`B?Z@Kiy9#E;~~n&-As>g<22g8@>v<SVf
=$_$Dsm`FvK+)%n&yQBh<x*Sb#d^4WL?Sa<fovVC2QPPXOMPNjzpqmnEX>zP_A7mfO@*0c3WZMCQ
_H2H20h3MSCwJgUACVGc~_(m?=9##_y9K6rb^~;$)<D)4mQc&M^zCeG{JG`K0MMj%d{P+~VE-(N?
n}RaX&Hi0vN{~ybe^Xok)~SD^>pLQGeODILZ151<-lXYUY6i;R=-X6Y+OS|Wa?X~G;J!pm44n300
}dO`Fc!w{ZVTGFE<awXkFJdaS*>_vnNt-=;WD1XYApI?go#l3A?eTyY`}m*gM?kMO;un_+UMQW3k
|0WZ4TJd9;5Q|deuww2|D;Fe!%yHL226L7E}Q>)|G>C_=*uS*v{13FC`|{mss5)(_4FGmsS;=TT{
n6$JG@Cdz+UmFpLerE-`~PNCtAAqAspvm*vxg)dq$L;*n~FD~TjcM=Qh5Q0UUIHN<1sz|e!0-Ld>
+Zpcb59eJmR&!!+iRHjgz3{7u8h3FO2Et*~!(V9Yw+s&ZVE{S@Qu?_ud2(UW$^#JS2dVGN+(+#im
`N)g;0<C>OXu@zeOW6Ns2|KB?NQ>(Cf*ffS*FoQt%<?&;3D#<Na{W_!b74i$SE7Z$jJSjElTkX)X
SUB_F#!<<3Q_o@f;I961AvY)!Nu8<Lqm~Q2{Z^O8jqL3Z;R|>%d(Jk=mQQIySqJF78Xeu&ovdmv-
PHwF`JT+GiYU%XvNO`G#SoGogMbNc=$!rINcDrA<@a`rTnvoU{c**4mGg#j$BMtRPW&^808782`1
F%ha7Py)P18s9jk?rhe2p`rlC>Q(4C4bVtWn8Q*<MP=^4Vw7B(=n8bi|&wjZNap5ToSIuHQ8XzMq
!^M->k6g3^N9&k)Cz15`TC)+1lQxA#e8uaMLp8|?DLWXcG5tH#<%kt{QHhK)03>tS@!8@a4aPAX|
CO5QUKF$}V3|c~($Y4!&=wXQlXLD6lQ^ZUyV`1rTwDLVrivT$cd|FYYhq8WWFZ3vMU{WP^$;x76#
JH+2!jB}<!QPG!hC-RrLBiSeV~U<h7)NNXqa4APlpaozPK-Bw9MMJ+^!XN#3+wPF1cZaYC;0b|&9
t%QkUHH1V#rrW4;--SbBB0K(GOOS5XH;S9wJpT28iF?0oH96MxdH}7?0QNiKvS(iUET%8SAD@iYr
gjf|!%VJPoIMH&{eyy1Hf*UkppxUcq6}2zp)Zv`ZJ#M#vqdVe-~83Ud6n_2q;=)EBhH371<eZrvx
pVVn#1p~RkZo^so37?3$V6%K?)AHlb{>pDckSoXieQzduI|DOE35RLxV4}zD7xzekYbQ<g{#UpD4
uQ?>(h@*0$zGL^GrvhSH5eFDzZ>QVX+39K#hLtL;H7Ct3vi<R0ye#l&#^LMGe&A-7C|2)+6ys^G#
FCRT6X0!2i$hl!M-f{<{m}I+S%S<SkK+o&Su!1`tjeXpo$tSY7KE@oP@mQ9;dNSj7o_%ss1=-WSh
9jcCt_f}%8>KnaJ)dXhDRz?9&n%u2pQO=-;y{hz6nP0>?5kTv}9Lc{4SQu(kx3VT`b7^okL9K@GB
on=syJs_3SVkO%T^qD9TuZ9?e}~Xn7B!CpsA;c77(K{7E{T<*1cWK@1DTZzdr?<I7y&W`O6GbEU~
-uQ;sGiqM$L^peV|@vIRg*!V7yKw{8mBM@rRj6z~Kkqg;`mm&^upqjq&j`jgWSp`XNmO#m5HU$wK
WFM$77oFXN;$?L99-)-F8x;RsB*`aJcW1-9yMg&3)gcqqB51cdomQ*e>h2(V6IxfnRXi*&OJ*4CR
r_6A0>N5Y;C5{ZM7zFdv>kI6cwJ&WxsBXe1FooQBP8c7@lo}DTEkUv4VuwAY1h^vJSjRT@&m+zg9
B#3y7z1;-c|y8LrljH+y|XK_epn0J#oh;{V3ZA@2p0mQi~+74yvzK%Lr1h>{S(}(Lb%Kiq;=44Os
w1@AdM6Sqz=l>?7K@L2s?pz~{;pLIXEp1hMe$$DKX93K0h|2e-E3B`%vV24Wg1tVfh6PD+{3xen0
^5|rKam&&b)V&7Pb7D1&1EF6}2tFN?VN&>L@QYpsNk7f8%rGU^bT_?$Ma*GIq#v<~uQbe$iMdYJV
<PVL!2f-0p2+k=K6YM(}6RF{-xX}44<#S}H0#25<rF3*v(A*nfb)}Z7TM!a0z9}@DoFtQcra}|R!
xaiJt7GPFg6?UXiQ{$|TNflQmfTybhpX$^*s#lrublQm5(lIT@%MTz7gOj^WWCaXFS7I_82>fUVP
N~UaVeCFGchAO$dj}7#hE@i$wiO;W*HZ7`9IC;lp=Y@L!jBB)a#?dV<4m)(p57WquL67ij+$d4Z5
D9tpL{(y;+*+i0mx4viJKaDTcFj$^n-tQoE(<r``Q9$cq*>*czoXY#>zM<I4j78eK9h9ETWkdKAw
of`+bw3qM4#c%qbWVXUERQB38nsCMtMK&<Q1U~rYfHZX{y+J>AkoC-p6pBD2X)ZKUGHj34b(ay>u
*aV%tlZ*qC9RjzUUo{W#A`zsmE1%uZC?5i9u`ez3b`Gy@oF%}$#T&+aDEE{6h)fIeVdTa~<tuq|S
3N^VT6DF$03OJuh~i_7vyo&VGGpNSkOAT)cey!!SQhhSa(thXJ8m9SkryCS352WR<bQ`I)bL<9pf
K4Ol%8TAi+-Q!7)LoEQX!JujF2_cC1>vj2NlO=|LeosH+GA6vvlrURsCQ3{Xd6(nNJ-CzyDD^PHD
<z0G{4Z?K6k=k!y$QncQ#S1-yDh8`jo^e<2aX|HQf=0Lnx~QDQ^so^dE@3el(m*M%4YQ3*5J6o%e
H`5_~uWx9;22orS&`zBeOWa`VsnPmX%87n7{csNt-s?oIqG;N_gAgB#_Sa5LeOx$|$e<pV7m_CS^
E1Il=aptnpBB>-$0~<h~mp*E|x@i?j@-eIg%aU1y_bhO8tO#xYmk$=x8A_Ppv=J<(0}S(O^PzW?y
aW?WuuSwzb1}7CM=m+9L~$cW_INSB$x)y5Gn8yV`FJ?X3pg75qd5Xu<fd;XsK9g=1VQX&Bt3;FC(
Ilbc6y2+jAs+N9%|5)1?6Ah`+Ce<q0IRxc||LD#)&KB)Za`COn)Fohm;`$6*VX;p!JZ)JO>(IHYi
GE=^iY|!fS!^t$RB<k=QJtsRLAt{B=Hg>tF?F%{JW(r31#y5tkq2m%oKf7$Sh_Nj#)ZHS{Uu5Y^T
8%>F&TO<*4Z>Hh7r|0*M`7FzZ<wK0t{O-aMhz$-#P8_{2Xy`BI1E2^LFB%cKuPO@&ap%zTRhI}lr
=6F8@lvN%E1Xa9RIb@!wv*{Tp6d~adFOc$SlY*G%K*E?NCjFQMFM2PC3}8%9MlRL!`8=OcS!(qbY
hR5yV4hY`>OrF(ZNaf4Xl(>{@iLg<MXZN5(7)U~tx#AGMvpPQR7wf)a8R6&$LXbF6{@^)`{7WP9m
7k8t{2nHBdCi`@Q`1fS?An~+V*p?YIr!J4se~Qw)mn*pvP<KU`I8f>du~-N9qe_$12yA!H6`Bk|8
;9>+R0n1`k_%SLH9}z6yvH;FGpt>XvN8be1OrI8%GcVTnD9pzg{NPAc;S-IlX$WWls;LgaXi#M2A
3PmafOm0F+|9YZF48az<+K%14RK3v=mlz7m#5w8z9*6<8{gbcD8`jBf%1-?d$m_g|aGf|`(<x*A3
cOz=_(yFAc(x@vQPaVfk!4h~p;tradqUkjWF{(`puckZjgbZY<gapbLF{n-D7&<?1qtdS3s`zQR#
5Q*cZ9yh>K{L2DtFot$S^-)U<6I#beo^fP^%d%2oXTz^=(z&x17fnbbC;`@%+%y!nuV$?O3A$oj*
B#rJKhAHCern&!QVs)BB_>`{os2?jT@73-;hR1;bfuvXX!=5`ik*htB<->52PBA)|mlJfAZ+z$o$
O{0iEIgV3*)$LsuXVc>d8)FCAb!5)Sj`;c-z_d}GP&ZquU$2y3*xLwC+G3lmF^)KT<4lBX4609dp
u3{2wb0GWtq_dhDx3=))B9YJA{l)QY7t`LPBfPBjR|JPqtQ!D|Pq=+Xtz6JwX8n*iUE>j*Ou(OuZ
!aV<uOuj`CNQYK(!@+xZQXIxp5EsVd0=fXTl~J{dvu3CiSy))VS+Ch#9ooo}yUI4`+ji?W(!a&XW
9VP?gQabEE23O`pvpTRR#q&&u*DIwwY8<v@pv%-QDw_AQrg(oN0}S7D(2-CkInzxcDb^jRvis4TD
!rKq{xe=zjD*TQa}J&TI4#WvUi+bm9$^$x#kC}w8;<K-BD{a;zs0Q{lx15{-^ld*C~}X-C=xPty1
QP1A3@~KH8BLBui-E=4Z3g4(>;Nlfeyd^1Prz>Ka|K$yf1`j;s@HbCHR+8VCNBLz38&vJza5ClXM
6v>-<ULniEX9T&;P<dRIOtNkczb$7(*LX$I@XBbNqb`Q!`O5r5t5+x4<)Jbwt?>)JjK`PXGO0@KW
E-}N#iyQS#oHR{~8@zD34<4%?qF9Vu6!)tyT}6uyIFhoo%_sR88%>a{!-~EMJ5u&9N1Oyv2xOK_6
HGuSnM<jy6|gYNWbqxK<{C4hBoz9P^1N~<M=2WG;$!Kmr8(&y@J-ot3};}(YoZ90BF0PP4(w}pr@
T|^i^ma61}R(^9{LtG%uQ1vwxKD=oLth>7$i#ynP!?5^{$CJDC(1-(_Q7Vp)afbUV+FR1Qz;5QyM
27v7L>CciNBlR<%GXr$YthY)8eC#u2*PyT12P4%`-C+D{G%AYV~q!oR-$1YGE#8XlIbAtHAAE5p5
0f3yVxdzo|PvwjalE6Er5tbC11*ZmSLZD@&6^W+c{>~Z=45I&*T5&BejcPMr`U-dtBf@nAh@EYOp
Nl5TO&=d+D_wBFn`SFD}+<@&&&*!XuIkM7Kl6t@w*JS97Cf^0$Q`3ireZ4K<4F|*th<jm~*K$^n0
z@SzZ5_?77Z^+W9lZ&SyS>Abp=UbtGiCtNY>IWfq}A0s9JkPlN25V3pn;G%+b|OIEcxdmorxVJ`c
sal(2yq!@mh$~I)aRc(p|=>P6q1xC+)@hz6cn1>$+8D4+@#5p}agvX4i>QKtyZ%gNc#1^oVG$W<e
ZrhOA~SgvFFHhtX9>auqMebETMs%?S@ohoO8w-&*pYPpdAE^l;grjd#d<PR6~M2Dl_r(L>*_A0Nl
%w-8S3djOm(F-AU4B^k7N)=-tD4FFsaPok#i4>nemRw_y<;$8q^Dav%GLM5WshY1>(2TdzVwdY%E
MztPcI!kFJ4@c^j36?pNCCG53Prw$+44`m$8u&eo=t2eWL$Gnv5MZ36jj4G#qx)-L&KTy!s#|y)B
EIzIoe1$RfNR;LN$&DPJ7WTtviL7GE?HTs7i21;b|qzk-g4;h;Hz$ST!mhG*zAGW-R$la4Dk>~Lo
g53unzGUSVyc610CYqNK#A(1@-)V>n-ltNb<f;oBM8LnLCMnE==MjpJK~_kwpipxZvc{vv)7@RiT
<*docHE&&+EM;N<`!vt2d11{tTQswM{w`7vg|+Xw3~ZhCQ+NkcR)Jd?-0SgV(@q&MuaQ=`<?aj+R
*L?OM1)SgFQJu4s(w`fu+O-gKrMMO(Ob+3V6^aV?mqJWaHkBl}T6}C*H{+DE-RtIox13l$Mk$TxM
N6_FpRZY7Z!rd&N6E9TN<vf;RLN6qR!GI6ag8}Z#gMq%*;%)jo+iGmVX>tZEc7W0*@Q&qHf9t_t9
xaO5qsugVlw`NTl%mb`RMPQduAojrKVRneL2s|EHf@5#_mMGru*Kv2dXcEW&`o?zYA2SrpHu32Bs
_`^Ah4UfL!Us|=54o45%A_YEY2HB&;_SjQexfZDr+@he?f=Gbk3>Lm030JHcE+gnNS<^8%)VWatE
IA_-ry;WUWBudPhz@1`M5NM<1S_oM5TxVush4eM9L=y0bE>K%t_U0|7vRbVB3%C0_)iT!I6P$7lo
22FXgmrw!4tbjK6b6`wbn`sP75dY)0Mm@qsctN3PfmgjRd+Ehhr;q!_L9$2Kj{WNJ7l#w|qU7?R}
^58{&mr<%3wBrt5B*jNK;_&BuNLzBz3f_rDI(J&*QkozI%_5_$;D|T0>I5lqNNGXH*Npq5j;MTO=
3TZmFK&a-I9!kEDBhPX>^ysNy+}t-TbCHFB}H@kN2E+b%qV#HGI$ioo@@{qoFR*pe3SLV^DG`0IY
yuPSV#h|<Q{zzQuM)K83di;3WZ)2&x$0Tp_zU@Nq7PgeH0HPKF=udA{P3XPT^o#40BQ(02~lL#~c
>pDB~VT4-qH7qMqW{QgUep&xoJ*)I<_f;Zq{<UBZr7sAR10<qe>~jA%^?L!#G`B@{IbvQw_8r0r$
7md=6de2mm0+Z8Q?R`9`0T$UDE$>9|Y40ro7#RvDZ=Q>ia*-Ee-rtBp;mlTasAKo_@H2Fg+7j$J$
tM2g1EAjJ895Xp>u3TP=!x6;|QTFk2bDK(HPxCa+`95hze=Oo_rN?6)8Mw@}DtJ5q5(J2(S)z5=P
?eyC)v%uM8fxaVCX(?}^o~awz;z&tZDoBS<`?~Q_=n0W`w2Qk<FMYct)&bMP8zWAU!1(xn-<ei&b
wC-%Gsf>+Dk@}u6g;Jy*U@E7OAgD5LbIItivbJ($hyzaH-?zMghsj%i!e2zfeFU<5@-)Jtj+dT>d
F?&Y6hka;QRWjqb`goxtjTQ)bA~I-EDm(Nw`KZxV~qCS;s|F2{gy_*|7^#A&n$d!W5VSe+5%hSF#
-o&q|s__~NEx8^9F3Dk1E+Iw7Zof}B6?rF4W{!WI5GKGv+y%n<^7-<5tMCn;@T_GO&a!jR|ISpCh
jo>=TF|+Q{1V|G#1>~EqNmJa+>B!EES{Fh_3CAlm|H3!;tOCrY7ux6fpbH~H$(IuHF5u+SCO*vD7
*kOLm?p0Q#6SAwqi2@d>QtE>^#t}&vKa~9vx1<Ikh(#yb+FwE-XOnAXQL)moG<Cv21}h*y-uAf=?
Ro-LqE8Qi<@zJslSscr23K<`s1vuQrs-&>A3t#%DM9EvaIxpAfIO^Z(bb#Ov$(0jTAd~a(euFaQy
S>@tY4PZ{K`C6T|Z@+#$u{O>`L%YVME9J%YkGr6gmavmH>Mp-0F0%UIYGbbJ@w-M_;aytL{NmckQ
WPJjR7$qSxB5F;r062~5%qlBxk#OY`&5sNQ@jAsj2Gib{5{Oz05qmwts?+34szCU?R!DLmkxdvt*
fdYYie0B2Ev3z`Y^8N!2?8Dzq-VI<O;oyJA1JfuOC?S!MFc?giL-YYdshF^GozD5wEgTz^o3dtVR
Xxx7*8lVV`1vo-UmdreoxI`Vd`b&`%EuUN;w0nvN0{$)>yPv7_0i9R7su~Te}GQ)ESqCo`=Js-2E
YV7x56hva3mU2jTVNuR?@A6V_*)1LZTs}F=zM^yW`TxR}{#~AlI?0GW%}Yd+OrqIA#{C!o-lZUOQ
$rC+Ix~j|}Yy$zGTNQ$w+WL{rM(sx|feCR$~hZ1q81p4pgp%$sQwSV}cu{UBVR;fT|c-xtQnc4D;
Q2@A@4+S)SWSi*#IJe%Q~E%2$&v0wFdnoq-aRF_)Swz9Plz-k9njg09~feV;Nfyv<?7VE-msM9l}
7ka7H(Uq37a?Lq?Aiq=Q_m!OxxceeAjwl%Kk@u!JFgu4<)@T~W)KV<)*jNP5NhmtabBxDFbVla^w
M)1Dq}xxr0o6x_GVna@?*o)FiqNqQ<%=YV36JAxRL^x~<ajwNio~LpA0A2!Zb0n>y!halJ-i!*%E
j+N@G(i);*xDSG3G}|oc+HM95f9gA8ogz8Aw&5g}8SYa%<0*cKMY87vpw}_iphRC7UHlM7TT4o&Y
s)CFlSyr0pmTROfhkH@{1jv|A)e<|s^Qq<CP$QJHs2_`J#u@Nrbp#i>$h0kh3z`mQ6k8x9xMJlQh
jcAz2JOQl0C5ME~U0udMTi*0P9NT%#-#?Q!}F3Hw6g{8FTSvdfek1k2F@=_)(26~eZtL`imrtyjd
G(Ka~UccmB<n9JVHdc~cl>rOLn%p?KI+v0Pc?Hk{+ADCYXPpbvzTXj3s<(>RF|jzZcxKhEL0jJ60
L_hE;|c-C@7UOWhkD>h87g@panZLQh=W#pMe#E&<g(xyvfSTb#e?Ax!NMBy9(=KCn2Nyz4Ow$$ZA
YpZ()C8x4FR`Y_6?7k(z}AFr0``pmh%cQQBfK(H=wg6>Q@RrA+>^M$Y{kZn{t}t`Nf)gX2qMW#;;
gsco#V!kA=GB+yZ)qJs^}7)*=PI`erM^hl?4qqXuwcw5%W;lJREIx{Jpjy<NhhXMJ?uDQLe7M+A!
0H27}K&ZjbAm^=X_P@-YL-$=Q!Xerj&pViQ%>njI~R-_tT)zI<;>FHshWmBIYl^*R`)ikuEe~n0M
0od0Fc<54rE4X;HNqdVd{pTWa2un$R1l1-idL>BYx~_#XJ=9SYN-0g2Aiw{!HhA3QIoJp}Y#G5Y`
I?bepuINJ5jhv)PI{fAgE!j$j_5C~e3oR~<DWKSc_}7UO`w5zM$XSeJe6ccX%9t*G`7%@W|kPk8_
)g?iEyXAfAll*(h8mvEK$MZv0Uur5#l#RWxpsD)GA4{Qf}bk4YsS<Er$2}h>X|hPKpLRLurbvb`*
eLSq{W2SBz-(tI}`w(0(f`$a!h|Dj^>xTvDA!U3$ZzFYxN!2z_C4Fz3Wzaa>~LDpad@-Iv~go?Xd
rZ3oYAXF)$8jD-`UlH9*}A(f-e9g?wkXG8r2_5lkiE}(4lc=M&N^NP)*HXMTbK5Lo!aQ{d+4V)l{
Ao+rQUQncc{?yT*y84qF-QRy2D(7D%PNVj$2o`!XfY}@%eX6v4(y5Mns*#PIB4fCF`|2^vWS`;K$
z#)5mE68{*)DuUYL;6vUS$l*>LG$0q>gFhsb@vP9N+TBv|^oEn=wZ|L?wHRK88S#|0_IeHy_8%tE
1-2i{B6ah?+=`suNb%DP%F*^3L+bH0(q)0pdjkkjXoPEx!z_&2ciEhrA<rgbj&fnQJ{Raj{Z^-N$
?RMo`D~<Unl=vs{UWKBAN=a5HlHqsW*;vQ}hO^#Hd`Qi@3J(jLyh(wUmUM(xx#bbLC*wE(*?u7+1
BAGo;UJ#H2z-F8@AkR;)Xcw+1|(te9%x-jyYo27<joNl4oz?u*|-eD-TqX{u<BrQvm>Z);#U}Qi5
9FL7CGOF3Bik9^<wCWDa&>P8{4MU6RAsW~0+d(5ka47_z+T>A>(iQz*!*bZl?lMtwns0F);TmkxU
K0-`3No7OqTWPE7B;x?IJgEb6fBCm17GcWlg^!Qbx1sH*w#m?`gJl#>l#)6D_4ka6WUT{35Fb|46
&+<BXX=|7n87KQDK$*ya|9dB|v)ub$?lqrhc+v=AR~xY7vkD{+;KUF419>a*M8_4O2|Q%(U;|Xmz
Hi&jKy$&a*dfPX|Xo9i1M%r^^Z6WmzXzUNdOTjyww3+9N=74-hP~Ip4pJ6EuoO<JUMN<w%P!Ug*{
$EA39?)&b5rOs;lMN6NN=tR?u~{ln?Y4}@E^yP%tk({w&2<7^=i6}Ly5Rj_m^7anY>0oydy>IbbB
bd7d0Kmh``E-lvGRABiRCm-IuI{JmI(9lfley7tRWm%`o@kTkmQ~Um)tpw^HPhU1Wd(VzpoTsh`u
+x*%SH~r&&fen=Yu<d-rOpq>M=y?X(p(7JRI6krAj5X{E)z=T>~N4bKfY>W@I`XS9qAS%Fl5XwV9
wS(Dvi<r*JE}@*bX}4A4++rNsSoaox!U<zwTaOBsI)Ie}3O?^Don5pGqADU29n(2&{k6V#BYH1#-
+qBvE%uX}ravw4q87DjUoZ(LN=bngktt0%@|i$?u4$m~zVeDaahk#ihzy$oV>*7llJSv~*s^L`R#
cx~ya+2=T1HbD@<Jn$TC~L&|4m+^!(3P<z9rIA<S6D!`V>m|g%eO*#XniGdL-0;TS9g}znqqIwjf
y8YS<mpL!4%J>v*42t<xF~AK0gj>lG%g!QI8j+d)hA-(b4=hd;9B%W)^$nTcuumqb)|AW1p|UemT
6D6Xz?)`qP71rCz{T4@dIDSr#C3X#T;~z;o2a!StrhT`c6-%KGEda$0DK-KPmP>X?fc%2;X)#j6G
9WpHphU+FpU3ApSUQ>E5x~a`;T>3>EU*85Iik={pFr6Ka~9xz`e4oe5k4<gQOf)QhK+q`s2$DDdM
MyQ8Vp31H8B%#cJ$VLgj<}Dx|A-bC`HvZ%jKG_FX1dn94vhtL?Wr6RenK#hjr)cZbZwOn9W`p&Nd
7P9uw?A_u%BQw}?<e7xr3t~On^s@Z$lgPc2Det7f<#(Z>yNp564z$d~&TMbxNjg^)*s&x^n=GH(3
YH(=ajAu{WV$4X@H;e3}N;O8+`doQidQ^2LqAI*Luz>$o!FGjJ!-3t0YU?9RI<}NWp0QzzQaxhK!
TRajM~WrsdZ>){iNbPy_9nocGm=MUJOfJUrs6TQ@4Kes6xj)n=?+b$ek*g<8Pu%Hi5N_uk*2!`o7
{_)uq&KfmG_@}9%$oHyU%(&ebpOdV~>krn!201K{ac67=dOcW*_?%!8y!9qxNMV>U8Te#tJT}{am
tqJZ09~u2PuiAj;l#m8GIcidL<rsL<xJL{mt}?twS9SCCp32+WOXj_q&DB2u|6E6az7o#SQcz?$T
~*2fNA*ry#{86p=M@>U8{Lg$dsx=tu}Qq!82Enc-8)u5vQazslS8&ZIR)RsZ%LXwh|{B8yyV?(&=
?V7QE?_%Mnfr>y@+E}qu&TUt89JWkTR+Ps5oQ2USMb5a=#YL@3q;l)xgj8#R?8{e8ervF3RWFR-X
I>GABp@p4$?T;fCGyqr6`PXLAxzJgl~+(%GVnQT2nWH;u~+cPE(n9@^7Ca>pbI+89y)@nh+jCvok
q~Lv~R-DSIB;qW$)hq`qwy<^kH=c*mefWj9dj2;6$eQln{V@wk_s<IsN{<O^WU;8>1^RqCaAa&$5
)NCvQzkm|YG?RW=uN5I^zRu;AJx6T?zBaG6}ESw=DN=fZ1|Y&C({;q6Gsz)M;(=q<2L>25BOeMyU
9WCQw$PL^4r^A?nOZwte#yX;X@EHgx0pT;9{IB1dy1cx|V%v-_VQ%oQ=*8x)CY=!FWM6Acf6}Cv|
o-EhSBAnP@mVZpdMa*+0B}X}r;L>Z`DN^~M^d#s~YA1bQ<Fhi8!b%B0E(R2p89gBI@Q47ozMRo1p
b@Ed)aIs7hPxMhA#lERnO^I4IudU={H=}-RJ@COB!B8%SYmV7L0@XAi60O61`j`$VDS0M1Aq!Its
C5<z*6=YsmC3wc~x({oK7V}ic;+93BQ0z(jCFXS9sJ3ttSeieY|4W3JIKMT@T(qW*8M$;X}^Ahk+
s<Zlc$&!Af^8GL<xD?lsob=tH&H^CySi<C!IVyN7b4zA1x`m<Sy~iy)o#1v3{7CdtT+QBhM*s`X3
6YNUEVDT#X(C=*1#X1+Y2=lPtn_o&DK)KvLe;pWgpPW66+P$ag00!n=&fU83wq*vt}a)111Yfsg(
e@sPGJ+c*WHqGeEi4li)8$n}=5`kTL?h>`eO_CXV#K0pRS%)kKV)k7^w<c1e7=d6#D3qkdym<oAQ
v@r=g2^vfAw&KB4-+jSi&x|$gCFZC5WOB7P1P$SuxJC=fj9?qDs=x|U0P*$MKOi9smLQ$$(i@ZcW
=J02+mfl9P-mJaTBZ5<}EZV3t9hq@E8D{pU=?f;QYQ5tH3}?P9aOkW@i;^VrsDfpB%q=L7uJi5)>
6%2TLBP0}AVl4=x-@wHU^k2RYAmKyC5apU1c{>kt&B@{R(f@r}D7kd&%BN;G+yP~_p1-Cqp1I(&J
BzI?C;(48Ab<CRoGg6h&s&~U;iVACacCnjT3^ne%=E4Piic-abmKuRNt4Yh;}&XKanV(L4ww4oG~
XyaQL!V^hNB((U#&QuA3g^S3x0<;wSF=an#c2qhV`28f<+p#XR7p%AMxQwJKQ^t<PZj!l&DDoII>
A+Z?b^S-Un6J{K_g50WhYQK=nL1^X$z+4i4=hPy{wVuogJG{r{8qD#*I0_4*+;N5jN=f5>LxXE13
4J1$uShQj*Q0QpzC?Q;wa56O8XG+860E#VGYT>uB_9CbbRJJF|Kx`0%a+~?;$yVOGH8hf!?~}BgS
`kEVYxU4$nU-q$*P_M!0H>Jz)Am!G`-wd6(MYa9M_v^<o+{g-i`^CZ>NWQl1L*PGYz(;r+`kIYhF
tj6Z|C9Y{{*PlX|8w3Iv0n1$^1IRVUc09a`tim{3Xix?OxRY1Abk^N^wS>)rP5xrKVc!Q3;Za3s*
v^u{_X_Zs8*x=SYDN(8yQT`*c6@OM*aw}<8?illN<D%i)%r(a~R3;OLGJ65}qB{l*#@i=>aq-so8
+g>1ovp%3eKid7$SZ^C(}^dBrepnp^o=iHKJPu=@3vYk_Kqp$)!1<lWYt1Vs&jQUY+|J*)S`ueZr
c=Qflt7|SBq+9HFAsdn9cAkfY8$tJuL?RVZ{_)!&>xOF<WMl3IL0?M;R-vgtbv}QD;ec0Y)27h`O
4z?~qFp`J($s?1kch68*(EL>O{W!&TMASIK|}7ZM~_rv5wZiTPd8#Da<&5o4LaQA9aVF~7F%t1+_
#SsNCM%W(G1*^{UJ^Q}kdMfI=$@hx4_H&H^oy7)%f!ZBiC`4~Yf9WW?k7Tb(;GNZuv>V6&`m9fAS
a^U@0{{Sh<DWo$iV5_46&}v8#A0;Y4b$6RBvTu|-H|v8(#%91F!OQ(mA1^q}pQ)^RD@7aT&O?&dh
>ceCE`^3N{JiN%oMc?kP-++>?&LRx*kpf@;N@)Uq`kH%h68Sn(}mj7K-f%%@uEm7@qAUV3?30|YG
m(4Q9Wv64=U`Tbmx)GwN6ZLYbO0kWnBLfqc!C#6Nf02Sj1CN-v}HiuamjU^4D#oP#u%l$i`MNI#b
0MI7OZHL0Hu-YhSU<<#0a~z@C^(9(yyVsWRCB`jEFK`E6obnh}YUnOVce3b(3E&}@iMa5hn`nZax
;ak{N`u_+nMW(Fo2Lu&C-WkVhXhB_!cd&3ptD65p?Os&ajI^+a#@e<EXNb+bZjj~}?BGt#A35n(u
=mGwz=mo9d6-lK`Ay#mq{0g0~<4lcLqElRH_R!#!80#=J68*pqp`)&sJnO7h9;|w;oO#_A&bN3#T
aNiHhG3|~^IHKyDj3HF3f(cdf)N*?1a+x$Q58D^%_t}FY^gogb=JW$G==4fp)*0#CvQM-_5-5V{;
U?t`h=pkAgpq<XOuQ1oS;m2h7q<d7#f9tqPAhh>|i8NE*IagEa&78;K+w%Xj6WB;RM_?e31Dth*3
2uR;Bq$W$=S{Ivg5c+A3ov$0W}V>6ux^h+@_!qt;cy)x7w&;c?ao$*6fB61c@}R6kRTTXUKy!v}_
1RpBSwPIq-~LxEq~;cgmje4VVfS@`j21sFe;>V~94(bJ&Ld=cus5HA|0%?=sLQr@RVu!IvV9C?$3
!hE6r0+o_&9kz%rkLYp?W%CTPVRc%2EsMNpaZrp``Xp@`QC%?@h=gh445X}tp@m;bU0?(zl+;c6U
DnXCKpa)n-7Mx*KeWnJ{4mm40ozavRm2$z`XiyFL_m7=kDr6#O-vdw?XRi>p*D32YJERXvDPHM7C
Ds5MV!$m(M!<jMyqLb1<@A3wvuN<3A05V0H9?MtHhU($dLmu^*Brx#WFC$Ul{?k>}Xk3&<L4D0PL
NXis;<IYb-h`XhS8lg6Dc1Cg4nkUf@ilrO&c@i!@UA?h3X(O!S>%aN!FwOQj$=Eg<}k45M|E+>g?
0*rc_7LTb}sxt?#ssZVyw`8SBZ>fGM-l>lEDARYV?oPPiQkxizJ;J3x-IzdI7*l3c9sp4|=Z}L+Q
_4R!taFwl}>8{S3a9SkBO1AOxo`P11^wO8*#!Bt!cv0y6yrGUE(9wccI_b2L@J;E3RxbtN5qFP%d
C5cprX^M{utTz%lG*NKjdD+<QT$O2!J}wWmGDi2j#5X9qb5|Hcl}hur#yglF*lh-AID8H<{aH)E>
*C`Sz>WQj#=OGt?HG`)jBn(IzXnL6cX-ofsf>8$}6Yz%<$LJ0~#2W09PRfW~t^Z#9EDVwONcnCY1
cQf9F&kLPq2ps*+l&XPt{bc+XR@Y#G4CCd}u7L`>XQ9NoxcW2Tkp3!8S5E~q?U4}uA7)+wBnml6k
!;H6}yg{!y~99L68Sb?+f0#fJM#tdT;?okD(#OQjsMX~Z3)r2a=MZ1lHbwhvc@K<yyDNRL3q_Z4I
9O8kPC(;$9FKRNn7trM}9Lo3Cs#AGXvOcWD8+3tbffWpRDeyt?o<meB<KtOk#HIYs4n9c{CyjF#h
nn0(A6wsDcPFLp`@Mied!;uFx8O!_g2uG+naYhn-M3zS;z!YnF4@Mw3SGX1+5&Mzgv8K@sowxD80
m2RMtnd{d}oliNT-;x(@yKof)GcRkb7jg_IUC0sRG8C-&-puOv{jUbEbje)RDAAehE4z>6}9Q(yc
sau_zSC%$Ag76?YXt?QjJZ7X_#9BlqWq3hNid<2&?0Yf`JUHg&VWl7=6({N-USeaFhAq3vollj2W
3E9>l?Z-W0F*ZkB{dCOm;dGRj}Zj|g<y{q9ruo%!iPfdq;(|t+m87;7X=Q<eD#?$b@12Xt+QRuQp
2D8>m4A`@!GQFzzDp!YkU{2xrx&O?!Vrmtbb<<l;v8rJa6u$DaR}bUXiLPj3RJtg(Ria?#=s;&PB
w-tVDL@~2ahtXBzSflFX1F}9C9m0#8x0tfP=}#fW4<Ly;*P9F3YIT!(xrA*hpeyQirhoR2h@<@k#
nT#gqY>LJ+q9~R3u2x*qEYaTEl*>WMzv<rs3e~J<^Qbj8eXD&*Ui0npHZ%n&oa9gW!=bK*1LbX!n
YT8;K!J<HQ37M{xR#!>NkR{HL5xtMc_~RIigqH#ps{Zh%rN=upyH@3zUr{^!rSt`M$|yyPiRMs8p
;0}P9A$0Z}L9)7wiDA^6{vvalu4^90s{%o_kiN39IZfuQsX55e&{!PQBiw=5CSx%&%e`4&VW-~}9
7?@VP-Dm0C%A|?OD@CT~C_@~!6;@P|V_Zm#zH)`zpVDE$bk1T}E_i-;K!$Y6ffEDtq9F|M_ENqHP
QO25>zJ4tB$KcA-#^=q$J3iQI6Zm!vSsHBMcX~r8O*LPV{CYYUv4NsxqVzeXkG$Wqf~Iv5xHSZ$8
&OOndNsBa+i{!*%2RE$Z#Er@XB<A8w#};d>ibTf!yv&jkettfv5ymGx82Lw0%h9I70~EN*nzUzlp
;dKe{ljtI5h1MBr-{ntT@4vKb>+)Q($P9>X++P#b>Rl9c+l9r&u_{I!O&VXqsOl_T<7dny0QtR7^
4$4>rrhLCo<+cGLNaQxu~sdL;;oIJyS_{N&^MsUyw_8LK(f80Zj3HZg)X*m)t`;p}`N&}7H@v7Ql
cX`Rnxi*hvtsYC1SDZXj^eZ-P7kA9C1ei`~I84Ul!yOpibv!-X^?6Qn{<Rn-{B%mTT)0@{;VdsCs
@W8+A<8XNr3xIuz->jH#6m+hn`U8;=|;K|(d9u$MMk~DQla^tGP-envgv>HNPSoM8gY0&DfBIk4V
k5SB4iIERmT66%>Iy@E6dYYw=l@mw{c;uUZ%iqtbZl&>k89ge~YnNc`3`1b-ioV6tFGTVv=CAI6Y
P?d@7}HqG)V~!6?0j9V#qA;J^&Rx^F`v=(9!^c16YokByScvLrJIe=$0;YJWoMARX4^W2gLx&L!R
5-N<o|T$cQ634{g>ZxgC3ft<z3Gh9M%7=7C?ps3`BhM5`6h2xe(-G`zV<i&-(<{1_0a5%g;6%e4v
W%Y*D3W{n2nHEtERD*^oy_RSsa?Ei_UQ4`oSZ~b+!bZkP@^HFK3ulW^ck%$~%+OI>(A^p^blw%Na
l@mHEG-L5+CXx-p_dmf8&D%*B#23q3X4-0J;6#9t3rzOMFAi$kt<35bq-pLIuR0@ZOyb!I89cxO`
V99a_lM#E1l2H$+0UTkuc76!?e)e4?;H`Et}<9VS*fBGMv83Y>vD}Fi>5rS_N6IRU2Ev-e_VEy=1
dKbFitsvZj7@+G6h8!x1IW;z|#RPp5@8%aEM1tAc}LayA~U$#r=;v~RxR#h3$Hd7c&Jo>ikXsqJu
?l@&<A%=)U=NH$*5?6`pi3_K~SU)`t#!wCAyZjWSXwz#Nb<$UYG!*=&)^*@s*rz^d_jLIcAs9l3D
7c9nTQjP0(9mn@}{$Y27&-+2OU!ev~d>Q|C<ZoAZ<Il-fy;|_tBx`laisskxrqcG0rdZ$WlI%^={
j=}i!|!=MZL&`&g-W;hO~rQ~8;i<!XYGD}=b|BrUh%We`f9wOLZ-)H8OK0m$R{8_{_q3*z%LRcS!
V2N;ZglK0%i|O+;<PYR_K#%Z5xjNQ5EIs)zzjrf2NL1>~q=#x`6{a9h*Qb#`u^8C!vOJWSB1t4?}
zqA`8&EXpv?A!|pD~);o>hjJkm~DVF~61W%8D$5&RJeXhfOwkt`US4np5R0263#Lcq<lIZcLtoR^
!24i`b%s#}JkHD(-n5%W1zHznZLX&Bp^~t5pth(3bs$Fl@cQ^T*?sL;&9}#EP-0$%K+uoWV5Vvp1
#gD^gk2$8nWdetM3(P)uV8;)J#)_kUhoX{I@n98#--B$7xWaB&wH|XVGET)MW>l13KLg5qj#p`gS
@B?J6^`GH<1C&%&$FxadNHG<E`2^X8HdZT*E?8+ZOU&bBkl)_EG~+Cm{PbjV&9gP7||m8oZ<y~ua
9eZryuP6p;R~{<u2UCLjwAo;-H1Zk>iQ9igA3dU{(g?_=KsmRbBhNPa~kNw!Gna=y;AsQ;mS!oeR
H1hGeRxL#4z&v{}{<ys;xB()Owiol}yti#0XKPSwx|Hy2g!VlXW&x*_jWLM0oy=q`~xsqk@hNZNs
Izf69+QidoYIisM?nz-I3km^ar$W~!}oBQNm$Zl5}_~8d?!oWJh7gXSUOV>o-PIr7f=PP<;-Y*ir
)bZL1ZRgHtC-bY18QwmU=~J1+j^`^aSaMQVZ&lJU<xfMV4J&jM*|Lcu>AoX&T_d#spYjE?QSp&Fx
Ht}+yE77zQ~;Zui<-IA7>p_kpOces74>X;>mF2;ELECsSnD;?dnTi)25`Fqm@DZC#dCBiTKpNxn?
Fkn%T5SZuK0L%eQPDVTAMV!?5>?YUgf1V^U!i!4)SZ@1Dne4N!ChfMqxbtClNRtkU2POknqT?Z4n
K+S76qqq*uvMQ5!$I#?bHo!%VzRemZLttLHS-c-%MLNF))e_Ho3U)&(v`PCvM&Uub~8vQxTk(|^R
D^>J;=dTtA5ZO#A(JfO|mTo3;8xAp1bjr5Z`?<8fLTnn9!e+GCyz?gkU`!$fHfc|EOsE4JLl`CU9
OQ)=ymR2fDxxVDviquJMxvtBU^OE+9<uo}=DaDC0OV$YSWWrnrSEa~YkL_yq%yqCa*~$iJR-Napn
`A2TS*TH2yv)9)vt&5WDId<vlXp|Y#HGT?4iGf`LEr_kGJQ9I*4BrTm|IgiWmb|$d}n6l7j$!lOF
(=h^ql0kgrkd5z>G~t=t#^2JdXH+@gv2(Pc3CUO|eJ%`8jO>$P!zvmaMvS*x=OVR$Q2n$}(HZolL
IOh98SD2B`%098bk^8Xax0oqsO!IXh6tCNS9O;w8T%n-R3YzD;OmTfqy=D~1WrVv2G=R&+d8gb4B
o6<di1BU2a#)N(W;Dn$|JVW)588*L?Ft3=N7XA{FaYED5UF@)vsH|Ja5xDw#UWNARi^4VkvXI(cT
nGgjQ7DrbciO&a&a)OOUAry^#uNf_#v|(me`B!=V5%Ef1EOt)!zNH{EF{fa=qO!mYf`^4DyFyM_u
5@{x^iN9ohvO7(+?bC~x#n5wy>dNRd9GAfJYg5PL`@$neje(@8wuJVDPvEK&;Z()q>|5^<M7nNL{
EfA)okUp<?Zb2%G*H&D3Ijq<ilNsvB5ljRz9xP&d&9wX)1E35fmWf%YVnk(L?|B{yUCazU9Bhq?S
dI2ijWa`qe{}pbkY%#ag0r3!F%BI;13=;UXy`RUp&t*FrG;L#Zog{Z99yUyrwPF$PNW>}0JlZhdy
DjKS)Odiavuc2vRwUSSUbE40+{bR&z-QQxbltJL?Tt7fsCLYAyryf`A@7Y|hs6m^kQllvlyYKAA7
bI^C_&`8Zo`vQJ4($+o*jEpwdIET22(LJvAY%JyUzA`y0&d(e4nVn2!+oCrJ91pJeMm}o?S)gmQ;
lk8t>}N}<Fb4U@L$uV<Jr{>+GgDfej?s(Gcm&IQAe>zX>A}4N{nG3WlAe;F?7V=@9yl&BBkQ^3be
BQk04{$Us92elGmzdY*FL@^*9P1L_ovhkteXB(lj~$1s_=b(gb<5#6eD-@6E(Qgm@>R_i&xJi9#9
$!vO5%CAvlPl)pKlb9G5vpvCuwn9MP67q)lKRZxVGffFpq!YPJjlir=D!3rV#^Cq@>`X6X=xD)Fe
K5Iz9*yV8w?rT0S3UduNF!p`LZx;!rr$MNKH6iXnwfWizaXDp7EymKL2eJ85PYP32HRDJLlnRmY-
91GxZ)Y?3NhZ4!@M5XP9b>xGmhsJ9UP$zhva?lW4I+5pa@%dyrSu=K6tkvCB;7ArMb9;Gl<Yd+{-
Q;YuU*;m!yijB^`Or?|qvH;7h@xoIj(@JhoS~C5o#rZIRdG^$7U8xPC1?AoddRtsE=Mb}%*55?H2
sRhkPA@RwR3VL&J7~Qz!<y$!K!6Vr$}Sbx4aX}UMB3;temGLy{HP3To)j@iZ(aAbG57|YO$)$krT
ZlR3(aWjrg*5k_b?=qVk#cKSX7(_CWO4z<BjO^sNxCR3kEI*HLZL3F_C&ddk_$AHdK%3^X<#2=4e
xJqA7AAuhuz!F>i|ywg|Tvkd@!)>MAM{H$T!D{h8XG^hdya>H&^LHQnS4(^6@y9i5SeuM0fX5}Fn
lSJj>64}~SbEi7Ap$-{q&TJX`pw@fEjn7&?2KH*H!PV#bu(+YJy#6ek`?k1z7(+FYsKo{Zs2lFPu
>v?#b`1M0aP$!$!orxOB^O-Dw9)4U1xu52N5KT$n#fZj(Q#2IxxK^G4X*-<$zINs<!?~c8X2$sXM
Pj15=B_zufgeRiDdPu*?>;MiP3mvi*-DEU9&nXRIRpqoEcue4Hu%$=5~W-@l~JSIXTHl%q)0{k-d
_5BG6kdxHmc9BhqmWorNVNh1r=)JhKJpmV;)?@ni}I#7wj}am9U&=v_`>zq9)j`%gPQQWaP0KPvJ
`_0XWAZKAfyFrzeL$8zGIc<GT%I3I(df4yEL9NG5uJKW$uyc5aYjr(^Kk2t*##%Gzb0$^YJdC^$a
>3=GG%Xw23*~B`N{>Z@|_mtJKOMMGnr}$t4QocS@q1foEsOXc2m9!`q11W_$&Fav^Ixav3%mT+zQ
vpx$)Xd5|AVSpGT~S67Nu=n)<EGf5>n_K9gBZc;!%aGal}<r~Nq~p08@F1y<GW@AU#tZF3(B)rWP
Gmh5Ug){?v#gr-+_f2`!ivYfv!>?>w^cmZtB_*naMjz-t}8zHfGZmr5Bxk56zHF<wY<@Fi;KqO5l
`Z8PgfcTTtTL^@XBpiwx9-ao-|yZ-w%djKz&Jv#&58qdC~msICw$1T5k|&v~nq{q=?^W2Cfdu%aV
_xbmI9w2l~3;e+1tETvK=R&-D`>gk{o{&sX=4qZp~T#j|q;Fu#d_+Z9Ik+%4wx0nsyZ~*j{Mx`1S
t}z!l-=drB74IkW@yhpFM)H>V!=po}dRUgHM^Xj)#RR2MLGh|aF7$?S)OykeGY1M}XWrjeZSLNeF
0Z^ND{j1O>d;v#Y!;^^@rB7U|EV}*bTC$(Ak@~CpQ^~rA@MThb;uF*P_GDJBKO!?%HVYyp>6;rXE
v+_T<FM-GB=H2F&$t$y2JA=vSCpDKU5#0wP0a%VckS%C}oQqUEV0P9I6jB-C*W?Ce(c)8v@U|;BH
Mtnj2M-DycsEE0#*@D)rVJ`y>d`VPzr9WQvn9>a-Ra+0c1OmIBf-B-69J?l!Gd<olOdz1ogj@u}u
ay?9^wmOm`&JvPiu*>GjRi||V&ze-R*ukb3H1KBNaMSi51>!Na^j@Delk%pgQdzmr%p=y8SxT<4o
=)u*W?){gI<C-z>F@BQ)^mXTvdo@Tb<rBVydik88)Myi;IxR8r>MS47t&UGUjM5{<YAr8pHVWOk;
yzat(gxI3S|$lYi+2@t4Qy0%!rtoJHFF2y$fhgQFPfF`7R<baKs^FhWU}!UDm1zht3Nic&^O66RC
<A`8>M1ie@iU4G)hs^U#ac$rw-J(TBGqRHTjz&f3;<5tp%NFu_^<Tj2Ejb{}~gy>7;()#BQvo*Xo
Ee|BOy2Lmg!1#|eKV+V?EEj%OHXp{NmZrgUnrBonG#w@_lmeElcr!KQ`m`aigw9sPt>Y5K*vYP|n
iC8ng!u155><j7KntU@T=jU`F5!f-=13ur)laXfSwkI4JPdB%=7xKY%#gRXRCJMit_)eicP84aaZ
e|kfjMl8kg?{(JVQ$Fm~%lD01J9EU6TazBHt%<{~)WnDDY6>#?KK#_xQON515LjD_W2taAU;KQ!%
PPPUf_kq4X6-0_AQbM@T2C7~gAx?GYpm*wM62ri7N!bi<vY*+;jwX3CM>=qf|B-3F}J_5sLcvxVI
pMIvBZe-6msw1CxusqKW&p^VoUpidqZq1XK1fB?<Ps+g=3U!Nsyo6;cnkIZ07Cm*?6Vsik+qYGDF
!j(&iy%Ob^@LkzVyQ9)CS26iRKz2IZ7pa}`4vRfoHpBQz4yK=<=uq0rNs-_KWUb9R)5Y6msgsIiL
G7>8=VGO?O1xx#>r$P?=sFyo}2W!`HJM!l~uNZq2i#PuWl9Xq#RrD7Q@fgW6}LI|F`Bn|>9V)JoW
4Yd%h25<wUMV(t2A7BGTj6@L7kprCNbMeQDt5uaFTURbFHshYQ)!+7^8S}zrLt<y8&DQB_Rfw`ov
K|Jz?KbTwtJ&^I{KQ%<9eG2+a9la+vIeP`Jd(n~rcmXglF$u;`fR5JV8ce5%Ze`npL_kLkQWvhao
y>wew9J|>y@b@NS5h0ek=0K6OTdZ6F)N|143(!7L#eHTWCnB2Jyyhepu!|u2>nX2WpPW`*Ce=7Mk
;=Q_nc{18srpSgBd*f809Is@T1f9=k!LLK6QlpQae)6CR)rQkiQ%9BC1(XgFSlGzcqp4R@ba<P8S
gDAkTyL@gTjN{Pz&mvRl?uNpE_=SRQ-QoIY&hMPf1CJgBa_ig$}1C;PITt<cHh%Xaz=ZC#ouEy-F
8_LYs&7YxfJt8A9xd1bII+?NoQYD**Zde08Gk{)jUJkrQj%tSe`kfF<Xx!XKG&>*kE54N1TWdw6f
|;32`GQe(C<>a;YXkjCvs#P)l#Oa=iu;<msA^H2$*T&cpXnCP`knSgt?e=!zE>_stLk0hkh%lG)1
cE{0hW>ivS~lYE-%+x384uPB0EEuT>4OsS7mrE_C?y{{Lt=5e<M$WQWtJHtb;Uxd7nS3fYHi?vOv
E!=m;j(<t!fPRW?hnIoSBz@E9xRoF(#loL|P{B8-HV2LpOD7?@ee(gOWz;|yI1@NEModT4pb(Bm`
lti1^Qxx%afTWvPRBE-?zr^jB`@N_^j%3#2RKNz6PG<HbZE0zW7N#`NCQsY!?HMTH3^K`k@=b$HB
7;m|Z-<sxGBbbsNkTdy>)5{5_lKJ>e5kSpRYlys@3>7YyoGhEC4a;!0W5oLrJv>7FGbWp)_ysz;c
hHj8SvsLW88Rg*)~yjjCk1#1!Qawn0R_Ot)LP0IJ_|Zsj%&{LD;!q_mT!?HfiWH!Y=mA}DeL&pGo
Y;b&DCN|<CKFF;Ci$mpVD%~kM5H!jd85FYhEwLFiPkioxT7z<{`rj0JGb8OwWK>&SQzKiQ#gn+jr
zmNqBjd&L!Fyj2g;FOhPz;AuB?Q54>9h>~{7jZjc?$=8kr4SZf8eTcp=8{lLGoImWkP9|8^`IuRp
E%sGL$qBhE2NT{3h?B)BT*T;hoC;vDG8tirV_YTgp*C%fVua8cj|9~Mw&a*c^z8*aP;pqJb{JOix
58k~$d42T$m%*#!H{YNBfUoxX#fRhPZ{NJIUv+mLpJ(v(^yt|uXzb|a@#!z{cyH%C`{BozFQKuYp
Pigy$qs;j_x||w{qZqA{qW1{XK!B-h<5pcz(@rs|N7|UP33u~OD#eNDvys|oqYf1_=WX+pJwLO+v
k5f{pH>9;N;CuQ0fKynUs%zI)4A`==9`uKxg^#xj<xem5+aX^Ze~===6sV^p4i+ySE=sPEX#x8GL
y4mRb&bZ4Ro`!?-eg@IQvLf$zKUd=I`qhVLDW&eMI2F&&P7K7D^QkZy-&pr#J}bm^x@KRfiZOFw(
`vrj)1QpnxT9yjo()0Y1`@_$$U@5%o=^8c><zlZ-Dftv=Gi*!61O!Feebu>U}CsdqIh5Ep7-QVJX
j2Itf(8Ugq)#CWcEm{lVUSjQ4^x{b+iVL~rlwM0(+akq#do|_h{i8=g*KWvjnX77a_MLbvXX%B~F
q|Q{3k=ZN37$ORDoz$sI)Nz#ghe0Ejy~X$^rMr@4##m(1S-aUcucN}P^gTNQ50rL3>#&I%zFLdS(
9TuiW56piLK;2z?OKYxT3I#Xvn8o3CG&N-6+k{`Ct%YNDMo55F2-nuUcs~U8wBp&MO$IJ#+LFdIY
GzIF<gF#ef2;8IEDt6||<M&`8u5CoYU`?FsuD>VCNjq)T#MQ*X~yy$jc!M!;1yeJbme>0?EiV-px
pf-!PZjP-<Z2V^5;6Vtmq_>|0Ym3xeDYG6WI{&6(jaiGglw~{s@1=&Fp4M`xl`|*s3x-|04i9IYO
l$hA2nC={9#zpsKTj8*r5;Hh_XXR@hP>0shK@|K80InjC(0%l;fbONRdf21Yy@yFbEaHhGJA!j9k
!|xnRSrDK3N&qJde5++Irh67yl-=0JmGSE4-FY;jLcT1N%FC-4V0@X!ktH#QBIZf#6{B6r-B>?Z%
-|yZmntEvqH-rVYZAeORSY?c_L`o5b@1JF76WD%6`e@s4=N`w~FEjt?pZy2pY8ePOx`dA^jT|RI!
{$Z*J;(Vv0OwlS?#Wy=n2*QFiU7#T~e?7d@1Iip4YdRB>z^-Q(6&QoDlT_|XwzqIZkW<{w}@eOhO
gM=ki(W?m+PsF}bv0y`jVG4Kv|n%Tl{-GsXjb|2cQP|RPkX|Z%`d%8x8A8-Rh?+~9z=l%g8_K;l)
!lQr7NbEUHFT7o$?$*p?ja`6Ao;NKR#u?PTsM07rwWu_{^Y4ZxL$Ek-DLnkZ<L=k)^VI#iML4FID
lGPeR1(A@=S1KxKU-J~S%?yLvCYk)5b0Lq7l&NHeaAdfaS?lUPNs9T?$ntO)i_B4tDubK9(1-J;J
JB}48)=Wgesz7I^(q%T$w;}OrbvckV__00USZcKuw7qRhw>&WF+OVjCV4Ua#%*VW@<yd9Gfl(3a2
H44I$eVyjaga!Mqm2O`L{sUCL{tENml|tpi;qLdk3~v1EK60@~wyQkvtU(1mI2k>4?i2TSyiY3!t
-&kocvPU0&(0OTImLXm#dXuaLQGEWUG)UgvQ+otcLWKa%UH5k>}J|kDbo>OGPWsMaI4XrAa>d6x>
Z=b7j5+!QKW2Jv_VsV%=2XGn&6n7-D*Wuh9iU44OBUS`&FY~cl(6lKy#1^46MK4*(a9^7sN#1|L0
-T4=-B$*M(*o%1uBB{E){VeYZv1aT=!#Ykzm{0b6+>9w^OG|M{Iw|>k=3kj6P3{d^ryy!-zrnW)g
4taD3<zMPD`e?X(_7+az(qbBq>ugiUhLKS~5l|*mzi*4Xs>9vAK%Y6vd8gUR?1QW3csAOpMf9JPP
@k@axfsi(UvV?Cb*hAX(9It+N7uHH`0bDQxu=Y`}z9?jQARSlX?y;)-knPnVa;fCQL|oZ^#h9P1X
Au}R8_sv%M^E!P<Kwl=NjF?;{ATyfSnWRnZO54a;fU&f<Ai_j#0xN@`AVYR_1Df9)2TC@I2ZBs)O
-2>z?4GAYZVE*YInql}rP)`ocD)_bAS*JHyz-ewOcO+an;EctQ=llvoLG7Ds982$|Wr@*E+l<i}Z
(%E1vJ0dJKG0F-(VfwS%F36X=Mwt4`a+AI7Si2=i&h5BwBBdd4XlMq5BV-<Ko=qv;$_^D6EK{FB>
bsIH%KLPzx=N;^eIk}djU|<TFx=o9^O*%WVO8o$kQUJ>oV+r1I8axg?%4zW>R4jD3h3C&(+2OXTX
$Jhw4xkR<BGNLFKl@r3=KF1E;*|*+vyS9Ip=GKvTJ2iM+Eu@Bpjc29aRo-psfF<8gYO5e5}7=tt$
=#?nv?FkXVvf6}cyEdBdNaO<r2d&TpyM6_;^BezlKDfGlv(X$H=^Fn}U_qYq(R+#ubj$3v2f8ynD
I-Df)n|x%9fNl;4s&CZ$Pyeyr-*S)?8bLGoWVMQSCa$XImUh<t4b)-?Rc3`kD>T$SC2(|0*N*$ke
JLz<+mTN_D%4N=4`Ev~Sq|&86ZtndRnNcCc{eJlQkiAds9Hg!-oU_R6gh&ePvF)079U95HDVvh?<
q3rteCqR<9ocA02Dbr{ZtvUrFc~1tXjT(q9}^{o?UwB!(y2iV#N`4Stm5zE0B6!YMOQ<)6>lyckW
=b&h297y6yjT?;dZ~yG{-2K6Srn<}78kmq&D?e+wpVqm5izSNF}+wKYwa+(YzgB!mb9k<1lZs3Uo
&qLss-9Y3pVH*7M(0Xi@z1tOnpEhOU@w}Mez*u;kepp1xFwoG~a=QqzJ8UktWI9D9rh>DGeibGEp
Dja#2Vr@VtDC3_MWKs8m6R)xX3kFGzXUm2#fYM~6A;u{fx*WSE;zOJnku$Kw52j>YXe|IR^w)Woe
-9n|hAxanjQ+qqD3au(C%gz5Ns$1^{ig^h_wjH(UP@>ZvL36bEh|EAH5s%mE1DwZwmGwY1+|&0o>
N*Fv``@+DaquM+n2j+vRg{hrOlPR)oFDo6^iv1eNf8+wYP4%hn5z~7WrKP-YsVrF#~Ik21-H?D@f
$7QQA?%$Y<LWvawV}>zf?lU5ka6vc5fv@?w*_@ucjMKh&lx)%X23I2DFkE%uw;Y3pX^FZCBwKInT
j=I_64Sk`|u2vgE$?BONUZ#9+d^Np)aB{oi{GXYsnLp5HGv7m7HWCLbCY+9@Ai2>N>r){=c3&rg#
(c562k8)MZI9qO;K%13=sqbRafcMlpp=#WfL*R<}zp5Vl%yXY*vV}MdtB1(HRu#FGnPrku*KKuvI
h6ybLvFq3-$KO)>-(d5Gn4T_4Hd6AhgX2P<g#K)Fvmj0x~>sa4e{1Er>~r90lO|HC2V>hOF8Nw+Q
8e~Ji^j3<>STXbL-=n3YP!qveC6Q9%t04+OK!>+o90mO&w=AL*(w>m(--(iKc$RRfepNDyngz&s>
`!!;1)nu>lqo1)0aZv-bV*!NsaAW~D-Cbtusa@?_;O;=THmbyHy;JFCj#s4iyd=kUpOyzujIpj*b
3Vi@*qh;XVVhBlqGgz7fp6DhnEytarHqYW)a6`^lea1UvnZnSn~wJ9v_yv2b}Id$sd>a0zvUx8rA
Xmf+L-SNZO=^uO^oUR|v0S21g0MMG~xZc&vcK%3{MlJ^HN(K%m1JrjNdN(JpAff9#HRO)Ed-oE4S
=M95RLU>SLtUvx6m&OGtHwIf=g-+R&E31cx21emmVdf(ZIU-i!se}OG$4x8u4c*>z$fLVvNqTZik
oMy=!tu?32_4^W8SE&kLhAf>YB2v-N-B01b}+<tE$Y0H>F5tLHKLn@#a{AeG}TDuYP~6Xj9pnXg~
TA!A3eF_sv<7pg$KywZYqnv<L|DN={b6(e`R8HToTGh;@Ldy=v+NVIr?FWec;W=;>4Q2FQm@s<eK
C<R0m}JK0d`>#!Igz&o4lzOzoFa>dtHk2?Rx-gP(XU3W$Ax_@@>igkgAN*5A6iD)am$Cn1BpU)Y-
x>(aaJgQl~BU}rP+TA+i>N@im>K68-R3d!c8OjD6^!gjcedIA=u&2;DIx(PT(2MAHH2RzYT7XwAa
ycx07H}d-?%f6lgcV)kA%0fdr8u_HYICpO+nW@}Wi$D#buwAS?9@JBZKpQhd}^vnKli9dkWjW}za
~+pqBmrX;HdpgFoO2s8YPvhkTLtc!3HWQdRl2^{pRTdz~8=P17$1;w990PxeEAdV(q5+n;y1QZ+-
^OWH7&d)*Np<0@0PP8$mG}28Wh9zFDW|vikfaNH<}6D4_kez8uTbzpas@J+dqk>V+P_8I0y)v-(8
g>qS=+O`DhgZ398KME)Ai!?;N|#Ld^><uh=yIX==gxY$5WU^G$hn$~jr{{`Y!S^XO4s?E5s@APKZ
TzleQp+@*q)Mk9wy6NWQ8_?>ryQ9!ng`<^GIhh!!XWN0R&0cfMVc@Rq!&xo;f0^>f)a5*>C4CYI4
uj@uT;Uxr7JTZ}(R_~HO13C;6^kXQN$uWLrw_u~p1{i$5@=Q~-#{2$dEZy*F55(?z0@>p2q=4D;X
!_l;?~c8*6V6(!2LDo?5>1oc&hs9R=RyPt=?8TB`CI`#-G2Nwvt;PoSbW6`)XEQnp4;f4u(_s;_Z
~T@@M_4!eGx=(>`>68>(ISGae=xD%`KgmejNOM*cN9T+G-iz`E?MFp~1F+cQ*8q(It_MlfFKS)Hp
R0F=>=YBrx$S*0-91mXGq_+VAMMjqqpy=b*IF1{>qBlal3>9-m~e}v{>7m=wAZv+LME>%|Ent?Q>
mro9LV^1{RSNg-Czm%%dRD(rhetGs336b;+>dAIcKXncfsv*&CIBv~z8TZcT4w2?@r^bUxPtb0if
r5kuFqXzf25VMj-%7Hp;KnuKFnB!929$CJ1n<ton5M6cYPJJXEtjpG^|OmgwSf#W^H{nnYo5y6((
tHB?>u!)(~ElUWw4>@O7QJ1hlgtpYpXpDOt7Zo!A4MBPlXy=ERW`;DoIdD+7#xw>~Ge7?6uzF05_
#k8CyCPp^iyaj^VI<-)Y0Y$cneZW_PY>V$lym$F7k)NuppHr!&fYDbB>ErJYI-I&;#?SH_y<Qb-S
Qp3gZe&0-P~2d8_;1~p0{<*0b1?C8i;5Q>Y@V0cMstIW~TjVMddA;o)Za2t^s8M8Dei^`}!dfax~
j*Z^-q3TA<vI(_n+mUrv&s@lELY9+?JAVhp^r3CHp(FTf5ZWpO%OI#S1BQ2yN@5!aQ_Pt_VaM)rJ
u}jIg=x!~sRq%ucav!xX&9TDW|C5p-*POtS$aL-0H;PoxcBL`N^g!5O_|2H2y&IU{)c#+2hWd#;$
t#S<~b)8fB7zmXA=$r_kNM-1jWzB31!3#fBp4RJ~o?Zb$UHR!&mq+UCwWEiod7315Yu=;IF?%Ee<
J%L2)oZUl}V7JCb8GBGnrZ_<&yo#Z5Yu;A)-6%}dPF2`#77cIVe$&olTSf*Ka+?W+PrS-<|uCi%^
2GQ&8FG@jsHj@cW@^tBky(&=16@=VS%N~n%GzX5_q8baYb?vog$>1A-tubLeA?gYm89R?koB(rNt
DVb7~<?AG$By+R`zCt_Nl-LxdTE|{fw)u=6WAs&AAsGAnhO)BfvyU7BjuR7Nq`MZO8=nTPtIK<Oi
@5rR4We7WO$v%6%8@>4-rh)(LW-71ffM84p9?tWV<f%cb;?N{r<73!2rl6$fp<6Y9CIX=*%5gvVE
N@qA(6CiF~%yVjV}_)C(PkqIW8b2)}mRBKPDN2rEHlhHtaVA%pK)8=4h`NSV8jCBiSdJ1i&Na4#E
xIpi!YzWss%;{#caBP&74O*3)3K$?cUZqS-_;#G_p?hswj7G`Z3Xfl+Q+MV~dBAYq(u!7rjFDR6-
=a0UU`buyx_S>A+cQXgS<_#^JpZ;oCcUzqXx(g}qxq>#Mo3mi6Y^cM_hARjsVP5E_M7!WR}%kzxT
jn%PW5y-3mcY$fJG71X$Q!<?AbPVMXR=kWbqT&MZHsgqlv=A2=#y5g<N1H!#b`d1&BnaEBcCWp25
KPEK9%EQPzyO?a&}kj?;OSL*y&xNVB8)u+0%%~&5r^>`<z$1oLXVg>%<2zEuig%Rd~<U8Veszw{o
pnFzv2B_8(Iq<1-%xu$UXl%IqF;z*MOZNpE2z=aE&T9Mf`x$+XO#i49Y7>>xs!Y$yOd0A+-A9_~q
O8uLsZGzB#6ld}_ldP7_R%@oidgPAGm-Ow%l>Jm{EDvINxw<#*1z)UY9sgW)*7O^0I(*f>~BfoTD
W*-xSON#!9fy9(Ty7w*gpcjkjT^TQn@=e)kLdoYa0S8hl1xu;K+y0c2%Sy@*$eJ0U2KOd{@OD#|K
r`YcV7~p!&oVVL<9|XxL1@is|*LgBraI_T3h>PGtB)boPJAQS1`u5EL0ZY&q7E4A^D>z1%4-O%aa
vk83#Fg$F0kFDH4Pc~dJ(bVyqQ0cz#h{}AaY;dGX}PcnNbVyKV8LNBr@TP1BMwfR^zrTne<NREKR
?_N#yN24`&RH0S4okU*$Z3k&cQAaE_8qJUvE#|oEl^sc6WChSOosz-~HX)ZX;;ogM)qZh5ffff8m
H5JW%3(*#1g59ShFmb_f6N?d(6UukHiWEx|Ou22RgAtb^Ty&m5K<cf*cZ>|keK`q$ap*$mFEnlKY
Rz5U06=1y<Jaqaow>~=5`DUEAycQZKR2^#h+Jbyul4!nTAphu6rm?i{shYmI*L`BhijG|qloKENQ
E(7WvY&c~dMba{WeX93(@3Hi#-R*1$sB8C#QQO^7fV#VzuCbooBYEF#3sv`ayBh*hWGxlH0!h1Nm
zrOPr9G!lUyi2zDw=?l9=8>s&Zb>b#NAPY;S!zR<Bm{ecT+rR@}?>3ba&f=Cx!8iIi#X*9!00!W3
<37VG{fXfE0aqc&UC(pA?06xaL=Ms^>>}d#^2=sk^_oAt*)UT_&W*J9|95T^U~Y@rIMv-L)aLA0I
HJeGO?t((LY8kiG`xipaZ+m#-P#fdlF*#`o9;^%Vo`wY7{xThn93S$Z8s2piH=uVX{n@9YbteSvh
)+YnOMg0!=9Ac*Q5s6K7TT6&7kyIk{YhPUH@`ik-G+MvE>fQr(4)b{S~J~6(>y&msTo!w3QwC@0V
%oNqz5s{;_DR1c=IFPzMhSU+(va{(9(|c?~qWu6Mb@v2K`@K!&%eD=v+a-kW@9#bSOoZ=rTs#q^g
WdM$PTfw|f>b4f&i;mS#*U(Lkp{n<3U+o}NMB3_JG(BZFQ$W?JqOfR5W>C#>MJPWpn|I}CWXf~sI
Q=fT}|nPk-hd#$03CcF}14+{eS`SS<aw@y$!dRT}|kZ8B)9L5W?Puc-mEjzC#6e_j&I%=wN44NQ%
&Rco}zgc*S&idvEu;8?KmLMdmv!Nqq&v6_xMo3ZyT`xT5l%JpuLQC|6Xz!@Jzq;9ODpE+6Z^9O-+
C$ah(9(c?}0^KrhX51(CDfb<@JA<Fj@ku$5^>-~S-J!^B@Mv{L8m6WT<7(yiZu^VN%701?kz2`VC
KlU!iuuzZ)Nw7hJAxKlS%m4lQIn#rONZGkB>q<ogFw-;B(>>GE(~tWPz7XRN-SP82vx_Xjw@3IxC
303@J-GjnSKvcgOdcHVdDwsGj-NtLUyg7k@&`;#UxRUX{`{+S>dR5CME>9h;g>JRxf1z9A@VOq`d
<#6%9gTrT<2+q>3%70e>TfUzkh?eR@L76yz+bx@-zB1i$?c=G`f*39@Aw(UEzIUHMhyCF3PG}Mg!
7{4ujiuu?{&~Y!m#MXm{#lo^NalRlEZ-<*KuHIVQo?Qj-2e?wOzzniS>NtE4{9=Q%u;Wls5~T+On
WzaIe9jyfNTe3O>hHeb5Z8C3p&CRk9zSEv@Xlt@sgjB%C*_yh2G`sCRgcioIQ5$hI0+xU1w*Bp$)
Vjg)Fv37^9Onh!$laIGU&keu+fS-Th@69mG)oVc8JRx}L!f9a=)WxUNAffa3Z-6c$%$)19<_^P}6
i@|~+1LfNgRD?DZ(~q>8=Zd0ms{4NFDps6LfZAB)+D8J6N{NAi`AAg!{LinR+MzvSzCDShLRKMoL
@05W_sI*s`nLMmI~<+Zj(m83G~Q};chhWw{C;M9~+C!;Xe6Vf0C=Z0p7I{+wtLjIBX!zWlY6~VgI
zI@Q_0LDa>Yyok_7b=^ymC-|Q9_(IFbMF-Xa~Lw#ta+`*S)>cS+E;v;#>kCPiJtZPh9JD&pr!XTV
xTyjOTyVF8bK?8Il=St9=FFC^j7o#^^jM}8<II1wAU~ilKHpo~FvmlH{-1|u@!l8DdfyTB0<3+Xv
Xf->TUJtZh9KFxCqcWSFP0=(3NED5dXc;&l3=EUNZbX_MIB;PpwEBhh{lQJMDm1SU_FBDu{rO*~k
Nx^pR+octYdFC~lzge@GxZjiyf`zZg{C&NZtBL9EiY>qQ3M_+wA~gM1b&Y7M?(FFb`K6PrS0A5=w
yPp;1?7gSxT~jr7o3{x)Brq`ZT=1f8z`a_$m|o1MgozS7WjkuuqgM@`OuW=F^U}_fX@E5<a8VC02
RI?dT)!NeWSt{?c%~nVz_f&`V}e97>SS2(z$`2tVTva@<IgR>F`BG$!oO*!U-oi+|CW_$PO+xfC$
o#t3$Nd@`8?O;Z^2hJ7KwA4SKF<Zs;X5jRC97A`|(qb<SWq#eOGXyEAP1{n1{4baD1HPEtUZ5Gpb
;najDYGe}Fv(VnfC5Dp(s$-auiDre>GQK8dw@gV=aa^Gcx|y-h>_vu~%odpxce#3iYcILntKqL>F
4|>M+%GAodmL>tkZY#oCR2})B15t65mktC+OT;+Kzq5&nSY_(HE+%5>m_XwELC-wNn(ST&=`Mfrq
%qqs3|&O7!_R5sBBBtCQiO9i?d~h)&L0_9?CdSWE;^uQif~E$L$hLpV&+j_(r8S+%L$g2e%0N;nH
?%5$QxWopPFGBX)5KwqvGnMiz9q=>|n>V*Z^Q1=6#bAF`=3a1wHELUcmgw%|^{`%A&5IkW8$E>vb
|7m?|sQl9w8OvxWAq#2!>4s`CqW1`MoK&P*MdGzM(tJ4;<OIJ*-po=&SYNvAW)&HE$U9DqwCUb1a
Mp>WhbXqJ!He-QUb|*GLVQZ7f<YR|7K6icF7@63skv85ncSG`c;m#c#$=m$Aib5#ZDOtPx&~D~q%
2Urw3!CU|vef(0k2qsJ@jn-HLi2jwWKy5A-1nXHM!TJH93)QQ2^fX>(&;7k3?P2`Y;2>?-ZhKDtH
6+5FwB;nT!f~&7I1|Avv<4YM$A&xKf?e5_Jc*4o#)WP_c$&nTIY*KZt=!UBh+?M96+P;_kaf%Q~S
d}?7M?;a8cazQ^O{jR~ej$)q>WVU}|P^Y+%TV+i#kcVMA1;dVWb^<H!_79uVvqniH~9)N0Vw3%I1
@FRCa56d<B8iyR(8k)R3WNwlicE9h2AreGkaFZe{dU}H75sl{WdLQ~ckgWl{qr(nig7p^yB03vI`
v~S?-OP15Kq_wX@UsLYM0C!m&+=zK*y-2awz$?EYj$ojhY&kXWloLR5!1Z8k7uAkMwuzqRUM1TLq
g1#G#FQ&mLF@p|o#<V)e>r{qPmsVYMe(3v6}$tR_#K$6kam=I(QbLp?guL}T@B=KTv?bsh(uv_%~
1p=iARj@i*t<6OJ`EDm7dGsh%srw!)L&1NQYd=6CyU2^2-7LiAkC;&I_~z(5JSb!`qM)#7=4_{vO
2qX`IY}1QDrOSq?JVx`6<moW4GNZqH{uduyvFvX;4765z-|4ezmi)nVKOoSAzEKvQHOd%D`I4M&Y
2bxqq1^7~}Y!I|k`W8c##TOZy0Vi`Zb!D?V79+fcDtGu|pS~a9+>#%_a_1lB>LhMO-GbHnAH46RF
yBDB{_z??}&9w`G{)`}9;EHtcks+Xss;!70>*(N`zkY<TN%Xq%YZoqMWED$lW6={1ql3RkgO98?9
Fk=&NWte>iIGYxV@uACv#Y9_sxFQ6w}~CKI2;*T0*P-~T&Hk0D{-FsJ|)jY-RJU0%y<p66}$*H!~
Kai`vG!tehn0pz!?0)wSCw!oAV200k;NBLOvzXEk4zSY9q=Upx%Ym*)CLP%k^atOc|o=xv@NEk0#
)v8pa7gRcb(D(RWdok^M0Go*Ljnadea)s5|$pn5Neh<On;AN-S#JHhh;m*YynnA18+%)YgMKx&hS
D4p4qFVvmTA#bOZ5ORROxWVkuSjtE8%G0YYXbO;C{%*CQT!=CWBt^d}ez4h~>Q{k!@l1$c%Y38FX
h%8j2qtJ>u=1y{SVcCY9CI&pAcanP-t$oc<INw?9Gv~4NZ20FLVGhWpf@5pQu?_Yn*aj{!4qiRb<
6G0IlKeNEy9O;MsEmwBV^4}{t;xpq!O=ybqhju}rw#&VY8nk<cqSyBy&m4JFGwqQ4YxCP6(*F@Tv
h&QSphzQuol|^tb*=ZAb1}hn-t^;%79rkEiNdXJPLdWe`>U%>pB-j%9-2lZ#UFGdkik41B3M29dU
t9I-D-h2k1O!=7=LRv8tyfM~4w#&#)R=ScAhf)_<VJ5DO*l%^EhusTF#p;NNiR`k^f&b*jRJSXiL
u6_&1AaCthyAB|emYBivK;8Nt;Y~aJy8OS{l5AQo^XXqPOd?C+-Qh`n+9@{U<H5_sCdUV|28o_I{
AtuKQs_Zf==JhJ@Gpr&IYsym8KX4>dISKs?ooMhgQV{faWuRST=s_kMHF^t{`2o6tP8H&;g0`}Tl
oIR3Bwxq@+18Pg0IqG6P-W^l9<#PErJ$GT3R6m;8{o7!XU7}{Hy5YGWwoi<JMa=jI6f2A$hzF^T3
BSco_7cpW})a=mZULC|1ye7==MMh$v5<LUC>f9r<^o)>E)dz<s$9^c|?+Ypdq9NJ}d5b2{z3Q&nv
gQOyhRE6PqZvpgT8)|C8VNOcs}Oa`=OzE*+Z&;bI}X<35}$=at63sAG;>%ei7TVa3+4aR>|Uva(`
%LjQ+tdN@Au95J!CxX<Vq4irjD1Nrz>7nsyM&oF%tuaVOVSUbbME4|d~*$jytDD%kN>FQ?`4|xPf
<bjAwgrb3@r2DYLV+wN`tN-G3!GvJbQR}(Sji~RwJfSj{8>d6$QF0ir_1v3Q;l?`8G)TJXNs>*cg
R#s$U-viw-*boX$ouN_<?~06Pfc7POJwc_S9zsZPUn(o!Si8igwi^FN19W~sDj<EpfCjiP<d_m2~
I}Z2RN&vK44^3xD9x6>TC6!#V!(8SYLp0*OV_f>9pS=RpHs1cz5`x3QZt3NdODk5b|qMOuYln=-C
#mzKWMPah(?hl6MA2qM4y%EME3(*$1|&$|S!Ir6^tWykxLTw3z6&N5`2@uHFfY4Kmv#IP3x?Vp~~
=ZOZT8{P^v+-$wsDee~q?RRlj-EA!Xm!$bZ>pZ|UO>h-f<U-<8TF&|(2`sDOAe`;I0Xjl9#en+S5
p}~<qp-C=~X_)*a;YD7hNhwaZ#|KB9mIy}NGOGg$5TiE!FhY;_Ikid;LYeAX=@<b-d?$H$ar6I}!
rOQIG!CN&7Ijz(Y!ydpM}j@a(=q+s%HNNT6&#0xh3M~A{(h9d8>a}S8NchN9Ju)O)w4&>!>OC$(2
J~09hG8i<V0VK^v)re-CIUKMQ)?#JI3s&&-}*F2!(SFXr!^&agVTAJ)GcLJ@##Ry<|8)KdNdm98o
VifW+TCdu#~#HX;LU0uE)L=#feHgui(<r^lvX5y&&2RaO13UtZI7Aq!t~SYu?(p_3Uf{}T68?xE<
r$=Tjr^*UBl>xJ8G6mwk9N+JR-0K9SU`rcsZMI0`&ugEm{S^-N(@KZEs$y$b0rB|-J?YImo+@+gU
Wn9I_AW|dm<W`Cs40v`oqRcULFy=4x|H;ipXaQMBzeM^4PBU=uyJ=z=-voA<)7aUxV0?1iHiXjgG
$a}`%rPI%ct9W%PMQhraG%!lLpTy1_rP*@RCMaow*Yc{G_luS0_>1C4m5d{H%I*DXozCAuWn!+b;
y1K4UUEar6uS!R*l15EBZ88^}7~#qSZu|Ww;>o4_J|fxUSu=t^3tn)SJ8Cq1*Bf-MNOB-NPL<k6g
{89W@nOPE=K-$qPGCr04HY`6lZRd<US)|A6Y~OM^t#lueng4Jh(kz?c9oEZy9N!<krrK;+^9;sD?
#TifFftDxrOlbQA5VWdBdgx=aO-oW1Z;_34a$!AfO+e^N3Z(&Ei)xnK@wQy%(`JUiQ5bURP?G>UB
bHHL1WVd^}@1oJ7vRcmBmQr#j#TLpzJ4IicDVXf1ZE>9~eGt-^|9?1{=yt~2`+jk-TlZQmz&wioU
+82a7q$=x3`V>_8aRFNglB))XE(8F*iB^hc~Q_ijCY1N!6E_n*;4R}gaTASv%h0JBbIBZL#W1=w}
FzI@2u%=R_;|}oI%*^@v3&;8`>TJDA8-*?)@i#Qf6^yKyzY~8%9C2JjD?lGN<8b?Y|Lo(YrM(>tN
M$WofqNm64LnA?-`9aP94MhfNgTXLsM$?t4=!FWk*3EC)DXzNBy3XzB<AVQfAIg<6IRHR|WYsEnk
AeP#|Aq1>i)t&vs>tct|^kDvc1ef{{+bIf+~yu;+SpDWq0@srvbd=|`*t*9U4WqG!HjF;u=qB%$@
z$bL*=+oyv@7KK!^ti4C`$>n{BQq^`0B2kcTjJ;<d!MHOd1(QLoJ(BV&7^H^U>j#?3boEwgVDzm8
DHD3s>_^g?TH`ku|dMXspe)?eKm*BrCc`;I4=A;770~P|A`FZ^>1<XAImPELL&bBC$bDRlcHUsw5
2K6Pxjr!Z!~@+gU9K5w(t>GxlByzj`?bIJiK{(|BA8EjFO$XziNrmM=&rMHzw7S_RiHbG&>1wD4E
+>3i=chg!h=Bt&SAA%@Ul9KuX|4s|0G{kan=tn1Y=SK4c}@)!rAw5PZUp5)3UqX#rA?wLJl8@ibq
TAZE6}5hw2ni^{e^sAz;x`YhZqDZApv8sBxF*t{ByfU>U6shU);=G$?lC#^WsH?%soL-`!u!NP(h
AwjVNNIO6riP&kT^$Jx~txlt@Md}dRHgf0h;w8b@)WE|{P;R{kKyC|BC8gWQXc*)f)FN5qKZ`Kn*
;Pj$%Kn<d3|L8iezq6QY)!C}7rUH9RcGF%DsK-fw22P96nh!eDWF@UV$HKFV|4DFD)&yza0t#_oY
GLux7h`+F!u!G4JW!tmF9q*$-a(UFnlInXP-ldR?5YEgAvQOT2ZHJT&ANF>s5#%JW(EdH8r}W6c~
55hF{Ia$qjq5>CgDn?y2vE^7Rza3;N3l<?}w!EgywA)B0+uj?-cNxNt2?7t0)_%;xcuVyB0uqv$w
YOb_a-4DB@*#W_(B#wrI%n(hT-4%9w1?$65#{hF;)2&?a59iVkMFvRS%Coq>N;fb?%E$^!9wean|
D73WX4z{g*j7wfwZD0WENlk`_$+fpFWC%mH`B@~}_Lr`C<-#9Zg;gzsp>A!fXwul-Dt+0rRVm%y>
^Ztblg%fN`Yv@Nu$rtF*<1{r@EdfA3>E1z51+U4yp`vV^8At1m(KU$*Lk^ZMhHJKR>T^Uy%m9-%$
PM2F2ka|l}&oG2BFTPO|=G6JIh<2(ES0eHZa7w+#|iub4&#E$%%PgbZG1Yoh$bZqNTcSw?z=LrlL
>Ol=wMdADUM2ROqUh<|%VA^byYrGGiIuEvC(275rMGCJ5U*8JxfN1+6gUV+;S*AuPDA(;}U(>zz$
<F>LsS4@Izli&Wb-=mcqKnTcDD<pri)<qjfjkmxY)xc27Ft4ELjD}D2;!x)rL*d!MH)v1sE{W3d$
PaZH4&M((}ar*Spn`i$%P5)PyC@d=8GgR*F%k($>CLL*Y7FbZ10OGvwfQvBll6&|ej^y`Ya__-#*
dhwF6~y))94ZTc8$I5hn?NX!U%qA53s!s(OX+F=vuOkKJbfO?48(Xvc77FQ3eBW%pup2})WBrtz*
xD@O%OeO`8IMH0MI=vQT_Af)v86l^tMSF^?GjXbzZ-H;m?!~NCMQcyhIc6dph1y%-?qqo<R4YZcT
ht)%K`y_#(S?Jm)U6X_3wA!9$G2K@mCPDEM%2kD_#_8GcRyQCb}_pA*N?{6pvFQN+2JqHK0npe)1
4fCK&}FH7|agQ2?!CzPfm+hkj}tt+fDn=Le;$pRPBvl3=L3GE3SlIcYg$81{Qt`+F=9W^Ux15k&K
@ca=_O@_4tq;86{N#TU<A6wic+PJY?;19fBCQQr3bdP^~{QUH_v*%>o5j!MP=;OJRdil1qNDU|`s
izuPIQWc1ndbAVpv)M-aDsBMd!}c=Fy{p7xTD7xMLA1hU76R;ZpbhBLCIwfY`Z2RLmvyD->I+EcC
S*f<>CsIUFMuUp`&y$gRlNLi>fx!tPu`hzIYnq&<`yaU*Scj7SyW2a~;7y16FC(tD-EwR6AxwI!2
%uh)ETQ+%yn9W-M;BC=jDjsZ};N&$q_V%y?N*SOSL3YRo<>9v8lV{+;v=LwYurpdb_W3iR%P4X`9
3Ik@|P#ULC4bugzL_XgN}igd8)5{}PnZ84nvN`kX!ETKf&c5>FKAvjbv`e4Jnm_Bf@m+nqTNBrrt
<Fwf`Vzx-ve<ylRi~xu}da4EYX6n0Kixi0tMj@3A`-Y2O`|b1qSyR(Bp6I|0yqGEt4sQapDppN;8
3b^sfVhh9goe@sE`Dxy^j@|Z7Qr+ibzBqc`TKdbnYT3a(3L!!MYt!dml$T}q8APc+Ovgf`Y><ody
r$eYQ19&dQvoVKIrnrkE2hYhw{qnKxq(%H#E@9^wn|u?UyOc{ptd*2-|Y>n|ja)pwL(<x`HQgz9M
vdn4^Ub=XY9F=r{&{y0YILI}=?W2F69bOTEV3Ms{iTq;V65QbHJt!+;9Mq$OHo0n)mvK)$f|+`QC
vx7{8Q!{O8B9l0b7t+#KncDVueqk<M%KRPVi8db+>7ekmhzO<g@-G@}H<U7O**r*i+#P>>K9ZW*B
)7uXEar8pCZKL*{v-?LG2N({<V;Z9{PZPX_E9zBRz4y_9Sir<YJxHHUFOb23JuAyCr*Tu~BtEQkW
b{d*XDjDg4Cj({QDSbWbB<l2g*mlO=AsHo&;*2s&S@y&p3z|j##v~TK2)c3n8zS6Wux;ZK^fVzV!
(<6m#9pG3R2FqTqCaFVF<*hsJgf~QCL}ou>)aR*>?ps7H3t(>9aJb1v)-w<Yl$t1Z|W?4KO7N4~^
-7FGt3~-)>4IhKZ6anD6Y20+0;)_7k$s!T;`tD=;f#b<;`EgLOFw?YvNZJKb`SG-{_6AC5XauzhT
pnVv24?7bsctk9xWmshS8$Hs4R_<4Ld3A#>;w|p4$kSCs>*c_oVyh}eaT~L8$u#h&sJ8(%I;`iDg
gU&h?bn#I6Y=(19^sRwsY8{dFc6wyk0gF&*0P;%bY*UztZN6oWuUFM#fj^*|)dp1%52BglG=?{me
1Pa}%nAI^Q=h02)-!rSRYD!6{fpKp=+ASMPHl)RIAFW@gvPsm+Yu>ar^2`YG66Q&Y+bHKhfXtTXo
|axtD#_-bdu7uzY!9e=7qX7A--x1t8gbdhAlj%a1OL|24gSgOo%l7vBGXf_H^_kKkiyWqKQ441Ti
cm8bwz~5Wf~Pb&=#x&3A+gB0xJ0F@1hDT0Jr3Os!03;?Xdj9oPsIv8W#`EGYFJ&zyikj8Rdb7cAm
EFxPSGzdH(0dw_3V+%3S`m*#Atn8}S*&zFD#=^ZZZI^CIHS;?%&*w9~dSP=@}!H&$q$3(PPHo!+$
F$wxXqyin2$a^kWNE@aL6C#zrB#;`^HQgYGVR#km&Nj40<~G&{cPyr)j7<Rgt>OLZm&#TMC#`|Ka
m%W>FY31x@m$OW#7UF1tsxZ$+*3GoVV`!zA#2MZaGs?FP)y7;73Z)O38~ILz=mI^D2O8kd6OdFT%
ec03RB%=f-*J}a<fOGC=r3JYkx7Q>%<P7F#WjeMOm<Nqj~u6h!xh}WQN0Fzo3rw98B?w!;OYxS~g
Y<<BixPnYb}g>s3sQkq{ujAT`$48i(j?N)TTdrKp?4I#So~FzLH(oTAXQZ>JSsM>2b*$R1P@mK2p
8n_-6`;1`?u-Nvdf+&5L97j`$;Xf_pYG6h~;n0siDE3RE~WD(IYx}^z+;w}~~IJJ}ZG2&^bX>DCL
XwrbT9b6cPN$89~)`=YQmIe^3og&#g$m-I~7i#m}J$>l%F_%?JMOQ?P7{KnZM;|jqPo#8b`(kC=+
dPc<_AT4Z#WgOfeQ&AQ)h3g=#E6XhZU1Q78tw;DPlz7s4TeksU}rVi1(#L5$?AGVKyPVM85l`+>Z
8XZ!rOfScFNRm029?!?_;{#H%QBX!H~k^t>Fp1OP^NjGs?kU%PDJ#nY-nPUcl<ddAH3i60V4_m14
GR%Bf4dDq+z#MV*^C`XnjOvPI%ILsg^JjYAgMGf1D931J~wpe|4r5+P;>(tc}4pImCvc7#Q9-Jvo
$X``G2_co;uh81fEJDeulQ85`(R~yt0CFdsLl4KH%Hrz#{=M<h1rj&-<mp8zYfUUu|fWrO#185w}
Z}3g)K1FoY@2J}mNSN!0u@QHV1SmNM-6&eR@B@KqR2L5Ao1oCmByi}1qvPS;U{+V_+1WgUnQH?&`
r$ZK3m>u)7)T=}x7ajgt#(SHXqq|;cnmcURI?het{9+v^ZEY(_;`nS
