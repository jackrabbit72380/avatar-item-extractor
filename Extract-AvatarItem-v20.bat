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
c-rlKi+0;avf!^^l=TFRNSdT%Sz#>im2ElE9lwsHWRgp98Hj`=*d)LqKuL5a_uIE#{RBYLiD%C4*
>x0&1o~NBU0qdOkKcBp+o*^ZqgkBawCAgx{?1o_dAQ6M4=<DSVVvFu^Hp(^rF$3Y#SZ@WA|7XxIN
(~r3_efuAX^qeb`>1c!{a=Ui+9oZW4p-4L6R0(@b=k%wxNOa{3gi*_$hAUV3y>0l3oYXB>fm%Wea
+^_aeAW;=4Y5nL`^vUSx|n58`Ni6GYfD{0^dv^q1iL`}Yse&fh-^##vfKNg6MLyPGVJgV#8y;BuN
l^)Q(PdkyR}3dT233di~CzkY6wv)LRP&g02NN=5VFCYw%hL{V^=6fNvMo&*G!;7wNC;H#T>5kr5=
=_I&}gX<+V5L_&Ko$h{+6flqJG`ph-UZgOoSyTkcY(9-=aaush%as5rI9@KIARI5EBF-N&G+SIDZ
$e9XJiUT}%(DeT_9DHH(<J&j4?f0=G@d@Zk7iOSZ#09uq_`o7!Nh_IEzkl0A51^p!;%u@1NbK^8M
rGRv}mfqlZw@Q3NIPxucK-FESq5I?D9h}gRgD)fK5No(yL@KgV{yb0N}i!q2xEod=AgB?Y=cIm>s
^Rg|ioG4pYIGQ3?y9ds`*(bdm?%?%w0zHeM9T7;xcX(CZ!S2gM?Z((5Ta2w%oCRioS6>tTugNBa$
$`MWGniX=;OShrbBs0yHYcKYT;ki+2OW{_r#RDf&HJ1+B8a=l!{eKYG>9OdvNzev07$KM9gG=oz2
LAaa)_`B^#U3s)>2AwvHmA`$W=>(V2M{E?(<2t#8;bv(J*pn83`m@W66i@)r3ZN3Dh<eanJ2(drF
<i#cVv#_ldAw*L1mb&m5ksp93>Be)J>12~^$j9Uo?WB}UJa`V@O7T$jC!;#ALD6UWN8r65^yJv8U
Y~cWD(s3MKX)q0b;@Ia!R}5BGqt_U61390a@c9jbm6I-R3TQOwtsJ0#e>2uw`N6A$YAlaFJr|?`X
?MGBzS3L6J=&0APGiSbw$1X3l02P{s(Uf|mC0i=-&xG`NkXOEXtlZ7i-(L<1{Jrz_meu+OGkVHy<
(sf$$hJ68MgCw_Mm!6v+#X0Rs_{_q@%ui^y^9;yL~M+6lHLK-Ism$o95I6#;-P9<7g6ME|hAM(t+
&2s%QFBZ#jVZN?%s}<PI`0ecU`!~nuKfXU1ot^&INpKW&?z{V)i}cy6x6l7J`r+jG#mRg1s@nq~0
j9tGyD5Cw>2$CiF8}8E^~o7L|BXpRrypGGoTdQKWOA|7<cD2+cnrgc5VHDl4<Db$_XTVW{csN-(!
SP@_VLl#O*D_+0$MH-paJ^bBYG$3qn{p7he&r`$3-*&6!<ZPsyXx?n_)f1QqPxgK+K+J(`<1b!N$
;U4@+(Q<h1ZR!r&quPl3MSK1bRcPr{S?aXiOqHu^#|;XN1q3TWS-`-kTWu5ldAOyAFv;*1_ihm1Y
1&Yrb^ssb^^I`A4vdIms%eOwTo<Wp33q?{Z;W3S*K1X9yBNQjNX^I$Ye(xe!TLOffV0fIzL693`T
Ha-Mwz(3xb?CJ{70l*;dMV@?$M=;17-T`3>somh4;Lz@Sd=rm9O2_GPM&<3!lPjl}U0o=6>h)q(!
hee>!4qGv-^C8X3jwuQrbyHtOoDJ1e!;Q-VA8nQ2_6KY)s-1e)9a|wuqS{kuzvj3h!6HRjuP90b9
<r)Kb&V+`C_NxftMkt`!sLiG+Ivm1-VJCyhnQ7tVx@<)0oPu=FJPB-at0#^;4h<?sT9i;L->&5h_
a$4{*ipQU%iLBjEGW@GxlEm73IW!!16G@{dqF>;_MsP~8Sp>bhl!(5ty1q79_;r%!{uA^x^{@s@z
W^-t)5dipCj*1+BfY;JLe<n9rT#C=6TX;r;Z*z3P@P`e7+ix`M#Dr5A~ZnQk4;tKtIyn_Wg+=y?>
!@x(m!!pLnIB2|t@oA$xn(hIO#2!YeUiYA);$Cla#l2p+Vp37@R$+mu<+XVW=)=eaZxK+pu;%ih+
Xz5x0XC`J*TH@*u-!h>hPMpJIha1e6w$ZQ@K)v)F^3AI<q?-gbF~I!#45Cx#J9i#Ke>WqO+8i5PU
)Eqrbc7X8QT3sliMgA$5r#S=})5`o1NCC$#ps^vQY|r0qw%l_}$YabjkkX1_1ECA6Jf{)A(ZNa2^
9=I0Z_-$jw3gQ#=M)^Gv^T&tqm2TmM)_X#sC1SR9z0%P2>t6QtZG2#5F4b(Tg`ScZ7sB$hq82M!p
IB-nVxO}_b9X7->2FzR=-0ETmk2Q8OsYb5cP2ZuGf-?rdt+k&6ADF~AR2^mJ~_pj*KL4B3g=U4f(
Z57~2i--qRg6KCvuidFEzp5!8LIsdB_u3s~cESVr_RTjS{5`7f_ETLmdv?W2exr;LUy*z$l1o5fV
1Z?s=CJ?bNnguBd;r7F`UiA|XbFEllET1l?jI-;ciQdV{~|PPb=$!iG}MAk9JA#24>%EHkYR!tSg
RFjMS@U^$Kz-g+wGx{O@cBWH$)htd^MZJAdjI&2*wc+N4DGQv>$i7jqieN9;Yo)gG`gluXDS(NjA
<OzI^-s_3`;xdo}@}@1d*?d@%9Ac*rfMEFdBSriXP2keMi*g4G-<B5+br8Fnvl(h6<>_W2^4EXUm
P3}n%0Tuf1gqN;mH9r`%m(7dd@5$LqB5Nx%+l~q+Mt5PeU*0=Jhs+CWrR$#FVmJ2=Db+^Db!OAWF
$tnNIE&mD1e{v4T6;SoAcM@_lyU6j`JIQXx?epI0^WN?A9;)6ueTLL&BlrvS@QFTF4B#FI0DI5v_
`Y=7hE%x8u;M?T8ny)a6Ec%EXU8)<BbaraPnW1@x=QZjNsIQH!9D7G+XJE*h|EHDk6uQwsHH>0VW
~-ca9L^*c&PUyX{v(kdsyblAykZ~vbLN;MJ~FPki;-EhczFfL39c79n>e*bxV>-z^&RY)MUdOoxe
qHHK#)G*yZMsSJ7}TPgDTwv4y$<?MV=ruZx?oQO_%yh1|85&Sn|E2uq~&;i%z({}7-^C;4G$D+?G
ypDSg0x7R{GuXRH@3YakJdRe314??46=UoGw9)CbNyP;Ln$2g%VnFix&hMXWP1oI-B=S0$3b&sH&
#u4gJVGqT3K>;{JN=j0SkYbSABUuM^x+&=ba^l!{gx^uIfO<<%cgcF{JmXsl={T8AmBPAhPn$oFZ
<gst<iiF-et;bqx!c#3urRHe+_I+biKRNRkN|;K0X9Zs!~Ks?RZ8ssDKY%mOjEjRlr#ZA@Ja)4kQ
aM}{b_VLEvf3ECkj1TA+Ye?Rqtnm3|i@*7Xfe>ju1*323SCAOK~6V2v#bcgkcR_8a7p8IL)H_5I^
eD0DfJ(3N+ZXEaDPZ5D_a{ETUCtRq@vsRoQiG1!!A>&{iu!wNR(_>AvmlMA3TmHAdmvq3N_4SW4f
9bBYdRg#9u+hR_*xx*je<d1%MsvH0brGQ5ybv<DFUa>P_5yj)&g#S54GoDdsI1^Pe?3e^1~H3}0T
G;vxiR?P3HFSL5N!&A9hTurlRV&pNx8R!$2oVw#j36EsZ-v{WxtBajq&cA<uvE!;>aI0XkM(`wX)
$<#VxcmlH``oCFzC0A_+iP*CM`m~1+YbN<^;rKxV<mvvV=ebjcVB^fjcT2%H&H$!nI7+M)PT5s!T
o7c6w`QwVnURv5|8W>$;6^smxEr<qM7cSJ$X~=v3D@U3A>}AL%OS>VO2VEG?o=AVj@1K0^kjB7n#
RT(EE_Jgk}8;zkuyyn!z(1)fb`rNW+qjA2nlcUBPD8f`;|kr#D<_uTukzo|1X91#0<@V6X7<T<j3
OI7>w}P+fkl@E;qs$G9CBxe629G9a0Xs$<eS2<_hF2qb*Ach_Wuw~|L_N6^M|Zp4I#(84E!0!^fZ
2mot8A=OlnuW!jTQEJm(m5TNaktuiJDVD3cvs<s~x`*<K-@R$K@+7l>YhD*w5l!WSha3OK8oMbc^
il0UAJEjyutWo;7Rg*xWb<VWp%AMXa%KlyGGrZH`uJy@XqrjbM82uU-l&8M?;u^X;hbsE$rn4!h>
=vM8D1o#R+R3NL;LcG&!5wilat`_BfJAjqs6Lw5VW51#dA}e#&i!_s7L(qCv5FD_Kq%?6)aW@MQK
<Jx`+C!T=oi~RQfHvUQd~}hJ0W3H0X93RJ{9=%gj*8ndc}l>8AExzSLyGwBgYR(M{uMzA>$kb`7;
$t=@ih8_;uYGYqtgog}>il)$QHcu<w6rwXM}s`18chSUtZrtU+Sb#I@Q4l=w@j|u4ZBVlZ`GQQxe
?h$XSkpK9yCNIj{G!CRVqh>$Y+aobak<0KtPO}_@m|}c`D32x<csIP70-J(z&OEt?iD?0e>UR3UG
`kB9cu^23=)P9$j6#57FL?3udACV60r>GzqZ!;J*Ec{xR2{(rJ_Ha;Q8GOW4qHju>K?#+?xH!h%`
z2`bXNHZ{@nrXX^?>mTB|I(2VyvI-#zYin!$3f$5J|fydlFB{v1tVvqx+NMOWDPkUN1nETUOVkA$
Vh?}4yzSnz5ZUFU?c2!?nzFIGW5&5DNC(IK5c6*Ak^3{jrJKj;hvryXe6uVGin)MPr`!y4HOMK6U
E`+|Zax&;`??C1|noaWLDM(YGQx4o{q;NpqHw#>3=$T0aU@fhlq3yAZxj&$VkxE7(68V%bGu|6f8
$n5&=i7E0Aosn8=atQlHx6*L8+HV&-jEul_BEXxl0@Me77dT$*a9{XHtr}D#&`>o7l6!Jo?C37Bj
0Mw+9hw|Ir4RIkmXjXQCwxXG4e$j2{%&^mXmNe{=-^R!t2QvQP2nvO#jZ;ful1Wp4F`LWQ@?eJDj
qRh&~;-Y_-6ngp=J-zHN3`$J$iVJ5BKrmr73yIB`x~HnuyWlz6e>kcW@F;!u#S8@7$yFg<)64ViP
Dr5I%bj(}AM|i2{Cuu8IuxBO$bNhZq|yfpIwuNZM_pStba+Y#dhr*EVs^8!<^rm$Uf_^(^V!!8aU
anVzTfHtx+l3{foas^P=z<vZ)*ngkFiOyf}qMob_)#4W-Snt)<btmg5NR~+RwfQG}qVgv9SusBC!
q_71&_8NnJGwAnQ-J$hd8e!(-2q+)6hcM=|M(i9e0cw}1^bC0$?c(x1d>HJ*Y6`K?k8EbxfB|ZMg
T*iJ_;1C$(Y6e?A(o)xG$=;|ggK!Eh$Tz&h1TG3L8_a=|KWi6COrUZyrmnlIv+NSX5(^&N{mI6Ud
J$En>nYq_tx9Hl8*iAiueq?LV!8!Lh*(>39a#&e&qETkamJJ6I5(i(mLTvROp)`IDVoo^WPyf2UH
xUq`q{AjdB$+Tk;ro`3;qN{X=ZSh*1@7MAP{VQpy4MKP;C(;j|Mxg_jkhHcbF`ItatZupkM-C_-)
}!4F-+p~nR7#6TO+_i>}5JH*i~I(k&s(W8ov9yNwgXaF<pJ$h8p=Qu;D0zr1z?;dysY6heL_Xb$5
+NJ5N>#GCH<GvqvWc{HKu0N7f^%XDxY3!l5hU2bPrRP@JtFDqv?(47yYwd5qnmK@Rj=ieGXWW6}`
b*a@9!=wdEUgBEZ|1TD%>X`k`E&ISL1I5fv>R8UoiwUsszHb%=Daibi0eG>!e7FLJ;H^L1{d}i5w
P3F7Okolsr5h7Y7Oqxc4Ru~{kfq7oaM(ajm^$2nz-Mn7$6n8-%yAMJgn;+$>Tnb{=T{p$PzIky$o
^?A_fAJK&zHEkR90@R#zp>7;ZGN#KzrLGZee00eyfi)Z|C7d(@{Me4-`?T7C@o^f(?5YX*YK=Sw|
N;4m)l^{i3#OpW{E_@J*?oIV}0!z!LgHsBxQj2;q01gy~e@1Gqj$z%aiR&-T>oCcrRzXH#0Vt2Gi
hBg@OOAx#k%M>lk@wy85g?Hp-(Nq^oN(`Jwz#@#J6xU#x$85ZdtQI#W=FNP!`JKFlZf9|UCKD{}<
;3yw5|LT}KUIi2zQp3OS1$Lp1>?r>WiIC%)$BJ~$SE^h^C(&5&g}`^BzXmZe)oGr(MAor_{A^LwM
%r|5{`sI#s5`&+ZIe1-;|ZOFw34A`579j#dT4wM)iGDEx7-EJQ?$l>c;8MF=fcvAvM9jRZLPfD~6
?!3H$#%*tR?vLTq~;te(qS&z+gRYIrc_zmS(=)~lBDVy;US+#7DqZz)deU&3h3aXmtSbF)EBs4ri
D)hd?rX&i3PZ#8u1jcwcBn(L}<dpowv>uxRY^*PfB4fECbBg_{m$PBAdNex!P)1$K1YmE(pCW;vn
MQoilTYsGOL!`Etpj!Uz9*0Vutzq2o+9XMr@&8p^X86as%tj4$rF#urquqdxwf%Z-G%ETLp7nUQF
K09L-B@erfV`)=3Se@C2V#YVlzj;x4$_fjQ>BeydT7AlUJo?cQenG0fIqJOPhl9W{U@b=t)71goR
m`VyZp7fulF?jtkp-C$tumaXz`(2TaB+S$%)$`Ph$3-jYy$SO;)hF9{aVoSLR;L3C33d%uCi>0H~
LLO#ROy$d^+7b8A}lpIil6;g2T{?lWc*<%<kaz8OtFJiwWgA8yKc!YI;M2P{TD1rh-4-X78p)v9Z
T!i8}Kbb)nko9lutZwLHKg_4Hfzb+`<C*TzV4HBPOLoU?>?tm`}eEE_qlq5_-D)zz^K~o_UNFWXC
ssW@oI4;#SVkm!`!Lk|LHiPjLUb}X@jOTAa9*EJYo`k*NJ%JAP5D<xL*l7(h-S47R0D(BTQ&vv6v
5+FuHq&H;dqQcLKT`OH91Zoc8QVPnZUF~!l3sH-1|&^iLu0G>lB8nzAlpAh5AG!(B6i502tX3J^;
R^QC<9Qsa*{T&$z(xZf9RP%PhyKaacdcdj=-MBH*x$iuipK1KcT4XLVX<QYoVdq59SSD1r66Bs5E
>N<xx>A%vxRSj1(3%tnS*^F<w4f?*QuF8EE>~#YnO>S39K<HmypsQJiOLs|=g<M{UK?E49_88fx_
2z7@iA3)Zq7hm7<d0jZj~P<z--$Z+sEN7pX{E#sppDq>LIb-qA<(mTAMXGKPbRs8rAzb-KVLx+Mg
(9Ql`!{#7YQvas5{;gO4M%VXP;`*U1soUTI_PtHlx6}=kztOj;ytQG&Xy6Q1&EVbuCIU)(xCMm`7
Z?lU(W5r>b!|Rgs*k>n16i$9@G|ErkiunDz;4X@Cc;Fh{E&3$1vX$nra{6kxTY#FC++iY>xIVir8
Wm_YmZTRdA;tX{RAC+6g}X3!oZj|`2|%#jZNiX9#zE%7;I-+IWEN})|Xg6AlqAe?U2?LES#ldo#X
ln0=?}^<`~8X+BT3u8zc)jPf-_V$fbFDxZc1Jn|P>t;Yz|ulW1kx846xnwuUH%jVwKw8II#8b3;~
g$)s|5ST+R)qO^qKWN3T)DL}7TZqf9@j5ZWn-fq`Q?UtxV8Q0LS1_8@!U*BL|*$Q9ahV6!Dd_J<g
SfaHLFijZlW(DW}B4#IbW@%CVo|7YuqB`h%k~%(zw7^>JPOg7SZ!V+=#!9#l*b#T|eLP8uY~lJG<
}+Ynpb&*W%2^|C5dat{BV3fOI5ZS_l|Y98qUm%Md|0L*+m3~#haVtdJbJW8+rmK!>$%1Pc(&P;GG
bFQat1B!60O*|pU2~Z)Y;))4~1Vejnf^G8xl!IFXf*z1sm)Ba-<vE?8wDfMfDy`f=L#$nqWp_e!v
lTLOnJL)Ulo!c@TuwV450KO+BcFgKV!sJViG$Se`LRws3%<)fk$Nu>BbA@)&P?(18H(MO(j-oi_-
=P}Fw7`if(U>7yngKiNLvntDh$*Q7^3{uEHO5i*2hj+l(^+KyK*_OZtelR@KtJ9uXe4CFq+XmUdv
XVYwHcu>>QOeSlS!wQmUQ8r&iHAl$Q5*Fs}CTrgVwn!sKL6ue%@xj#Z9)uMN9avO}U9z?q88NOKi
_jy9ba1d=)rJC@(m{f3`Y}PzB#a|e=qN|<C839N#1rdHA7```2Ys=_^TIm(2^+#m;1m4&`*zw`Go
^0tkO=Y>;sXb)`rIkrQuKrMGeq|Cv!_UvtO??Ge}Z*~g%zkK8%NU(XCmq%tYSc*Y{I%Nk>bj;Bq!
qJ5Kqgg-VYWL+ODoC#TUa;u2*oFH-o*NcG{&2X)EN8(lAxlvI=tix6S2*KGYX<*$JOoEN}fMA27~
^|4?Gjc~80T4Ft$uo)QH@(MRAd?z$e*FqEs`p;XBOtA0;@UI@nO*IxxM5pu?>lyn;GE5$Qw2d_CK
;Dn=cp}ynM;hqYJ=|mjh7Wejh&HeqJW?@*V!di3E>>}Bp-bJe%MKcaxhxP+Ei&&9*zezEk=1R;tD
Kh~+wlq6*g>e+I2h<N;FX9#O?9ntTwYZ4q(}Y#I6u9&K_s@b5wg>97dV6@C)_DY6`(dLUoN`#QoI
@vKV7}6nv+;PkM6-s6DpVd&pcyb3IHV78l;&RtlW6e~)mxgg%Q1cz^JPhz#-$<V<o(VeCNubzO(p
c7Y6<o1uo^93*HkFVNP->}eq(5P53DCT86$LlCZqgWGG1h;l~F+qbA)dyAwZ+cOxjHW&Ta2XlhIy
LSiu#+F`wwgrCn38M-*dIb%_KVgO-hesYy}_iQz>qWD{PBIKY8w`pP@HszKyc5cL)@l#Ca1V9|m1
feMA_>}C`%qkHfWxztBN{*PrGf3kIVZhLn(us)<ZWQ1A<op!g|Zg<+feFSez`zpAK#^$nQfx%w2-
?hUKY~%%QH<m!K>x)L$F=vU_CC-!EhQDe+6;*9)$$Lw5RK1_qP!-&RcJxj<wRH$jiVlkO0HNT)fC
;c3JzI)*6vN&W)A2+9LHEFa(%V;0{Q1c^OdsK$(@Dc<k>u53`PF(JLF$=NmD{w&r&U#r&BCR{3n1
&gnP0Grq0^cxqJ0zWZR8qQu3W=3a2Hk(i^}u3d*D_f<N)H}*H*N|Cll60Y$JuufD*-t;R(I#5Un6
V-c5fg-I^%!jiqQ4luE$HVUD-_N^_>f0IM&hVvPM*hCh`G2=3B#l58ixh!AKjA|Fdd1o~J+K3YY7
*TDNKI3^3hf<iIDxq~s0nx2Xaoxc*6BSRH%(%hDk=&D-tZ-CX6TB2@2h_(1S*JN@Q&$5LIO(YN3D
8QV7*{2D*r)|fMyJcKmkhoa#Xq^$RujfL;Ei1lq+6ze>kV?qEx93wa1rCMQYaRF+j(!B=zXm!CY`
-=xg;H_Gc4P;6GUyBkT5^($9{tTRF5vQC%<GgQc}HWw+1%*$QQ<KXR1WE?8I4h01wTc~C5{GNPtj
I@>xtehNp(ba=3CkOeG=#6MKb4r%M_{IQT5a5eiUSR8#`=Ik_C1Us_)Tdj(@EoSr(3C3^_fC3W}h
itKh~Dv00QTC0rP5=-L!hd8bi(_Bc&!8q#QVmB2ADYBXv)^1^Vc7UKIPFY-_i-{;#XRy#&JGexiq
lDy-T1Ct#AwJfe$hj@_)+}2f<-OnT&188w9ZS-~yuWr08z@x<*#%wJ2ll+KG3$k&;kB`b%^5m{MK
u211wHpErWK%@(vBuSiQ(&1faDB)P;w85^9M4vH5zkKU6LQDRf->*|Br1VWHC+7f(1aQuj7JnE8-
vnQ>|@dIGalnCM}#VblG`D&Cc5P8-Q=L+*zJFwy?x{Mc(+Ij@2cwm<M01H_{((aDERI7vN)wNmm8
=U4b>iaxQ|pjRL|so125p!BRa5lhSeL1TKsqH3u-`_s3=TqD%~?qMJ*v3HQ>GwLm(<)N1MXXTgX4
81hiC_Q59jK?%>=ci<4A+84er+;EK6&0*MC;)vuaeJ3!MG$^(MhkOw&j=T60~7yoBur-5lf%-+#t
6^tvF8jB=@pcXU$K`*PY@#?0X$MMIo6f8?t5#BSy&9Nf1{a-d(&KJmGhVy2yoR2Wft4oL8QSuT@F
u^?0FRkU=aUHqjyb}41i0sj_xXDnT^fQ!fLiuRC$Z`-3{;M?sUgV~4C#b-57u15-%Sd_(QBK%7D%
|uGK^QG&bUoChD+|iM!1wi-w?dioQSyp*@Qf2zh}7Roa!h|9Mu(Ik0~IyME1>mIg?SEizG_mGO5+
|Zz`|>Ri=BHnI+55cps52?YgE_yR9OcrKyR+;W+(%&R*tCrD7*X+GGYh=rWf&u2G!J3$Pucm-Ie`
&bQ{At0^I%EXa8v;t>&8dx3w`%lcuC;Y2XzippEFSzup$V{)+0SJIQB(hLfxtZK@5EvmqZdtQp=9
0cIItKtRR2l|$x<I-8zxLJ?vP@d7EEw<w5t1}KbaVv>(>@M7-;p#jVZ%E+a9RutKc%2KblSo><q0
rRwiQcoK7XiJVAL3<;(i&nt`FJdcj1O3ZwX@$aiFnFxxrBaHC2SKrzPLoSTDpYyp_QRnnyOx&>T`
wkS1*0xH!6SY(aOB)!ZU32AH9VNm0Ju)0w)irSVZ<Bi;6OE^>cI|dk$UKzSY}^Ygh;nx2$C1K-W}
X+@SuHgWqvXBRgE|SKIs^yVaY*EvOF2U+1g7EOI)!D>aHw7QYn^nTh6wTIpen7BFAGSnx3P5ax|5
z)EvF&xMk9(!2^X4bXeKy!{zNru?HO&@LI@mrf2CRWRm63hg?%C@HJY436#Dt6Gf_3E>WebZbYq7
I+fH_8V#kwQ^)gDa2TEnb_dN((e#>_7}Y0*SJMM{LI$!_LIULr8`Pn4+&Vw+pwh0>F8OKr$X57>w
j>j~pcUNORoT-=?EtNb@ve|8zo<@=#tQW?PGzqd?D-7qS43oQ3!kbQVro+{O+r-`rTE@&j*GOAI^
G1`7UK1!$=^f?BB_>`{NQ^}jT@11-<W1f;bdX>gJjrrzGA%B@}pka1F43k^;Q7WpFDgpv48VIz+i
YhI3)Pl(iNzpdH&I@UV4r3OgPM21&wQz**E6g?zR;zfLWvC9fos(S(uo6q=BOMkvuIi13;pEW?&Z
0M@U2}PXA*=W)Pvo>Ie!8r&LMj=n7HL0no>s|G)mKx?&E%Mn#n1_!<m&X*lY$yHt6Mz{zU3g(CZo
Ouj`CNJ1;Q;o!YHDGsAKunW^^4nu(2%BWh!S+i7%%q(m^tT!C49&V)ZUFjICI(F+1(!WJWW9VP`g
QIQtD<WTesLFdE)>h2_V2=|dYa2@?)9G>stjdmKq_nlIk1{uEm(0sc9-IHCopNTJP95D`W8(owoF
Z?U{@OzaO929CZjtNQ%HC;mWpKaNbFI2rrA>a&=}p>`33nn7>la>6@ZU-2X0XpglhACD6X&b4(zT
Bl*Gmi{`i|a&mQwe~<oir@%1=!Fp!H}h+><!3r^Y?Bqse3xNz*V?PBV#fT*UuaCJQluK}VYD96G8
<Ke@3*>K&T|Mv{lifYw>ys{ToTkyaD})Z5o>lQtq;#Pc{JP0TD_T*r#@Y-}74X2jglGonRe3XCvA
!o0DC<(yK+kd7<9ik8ztNu=YO3{T3VP`+R6toYBTby`C`UAAQ4`+<AT!V0olcnR1h3W)p7^W%Wb4
!}w4KPq4)t(i{~$pUI0GODul0S)KmY)W0xAM7kQ*OQ7H_BFp)ic%b@7+J{fGeW~oqh&>McCn*YR5
OquD$z_HOq6;NXd<H}Y+hm{u?Lg-4NlEbwP`tN(ohkGo!d7+(+rJ^Y^|Igud9`_?8?-zPz@$dl(s
UAI3{S<F-DN2wMTBKY%JxFO6pv~@s~BDDwJv|R<;hKN~cCub$j3{=Ej589?;uX?;z(Ek6<>`=8>A
#5uX2b$oe4Av0bg~lypL<=NCI~k;6fhuNt%+g|^|`bBkdXEaD}zFJ@wNm4~to99esAR9iAqrka(8
0KQJwPG}3w%gH0FUADF>7D--~Nk>iju~wjR3=S7&yYHB2@fsEti^rqb$dEgSHxAgVVT3e}GEfytL
T@5<5YpF*9T12=9LW+h1I;jR(AH4HYvLEJSu0}{U=ogz!3L<pCJ8itgBEIc0M)j@V>E>7Wz(KPlk
1dKENTjOi>x48sH)3BoM0vwM1|3aIjGSH&*jlb>ofV7zDRePJHSRPfW(fF_0P9S%YDKXluO0Wm)U
)=chFIXHnqcw=m=dGqG@)$j8#O?7QQBVgC&#alyevnkK96~?G~TVr%<+a+v`y1qauUNc|)05Bn5S
Gm#K860R1JdPMQ>)BUjne;c26!m&=&?C@?cP^Bt&E=G3Q)W!er@l3%3MQ-IJ#dVKc$^b||YmkZQi
_bq9ggeK!onyWCjfB;Y+nbG`y$(F$+6R*(e6pjDb5=}{4bRd$6Bc-0xDSHAs*s?1e31K1Td4vhF=
R83%2R0pb{%CTil1~M)oH-dLLUq)ro224s_?dr1C4$%(0>tuQo=`sG%T;g#P4pGgcH0cAt89ueR$
5r~l~Us*V&~Xv2M>NcJ9+=^{o9wPuTCCZz`qwDMpEhn$=6#|B+fq;nW*gdE87?oPathPswna{jbA
L1+qk03gH6R%_ps7vfJ6Yr2==rLJWrLXozulIU(hb{+aM(EGjD=vw91x6Uk=@i^vU%ynLKS@Vq}2
?Ek7TU+=J>v)gHbK9tOfiSlc2v4lrB&G&T<}Qjnc843zLOms~UPJ(|xZl<}D$g#H_O9<*AEEF*?8
kD~=zlxDM-Q4ZBB<hmVU3ToU$8Reu2CP_Zd2(O?WV3()t!F`<a2xNo^lV34?!>@+dY6s8g1lm&)B
#}YJL^>%5I&ztsvTlNptQ?c~w8&##?|z4kYg!vcc}<aGf;n*tWWa_Xd<h{3EN$F&aAxP&Npg+Tm8
^{A8ET@@^Emf>pT7-<ANIqPhx5rdjq0Xv9Vz6x<7EtQDs{8Dy}3xmhp1^MWf$9cHyb-&G9-!&Sjr
quO-C#GV;)^Ak&~%<;FJF{tMnC-7Y^A$G^431>D^z~))U@Ct!&XkG=7SXoQMOs4`j2gtuM&@qK}(
(vYgG`C+NF}(|XHhK{7Frjh0a2^u0c28ILkPZ-Y>zoxbWXo-}mL%MUI)k*iv0BFhql;uc^ZK7pQ|
KBVD3e1aPur83o2I$Z^)FaC*)C0Tnh$mlVdZW2A7<biPbxe^93zl<KxG?~F3e`8WQWOE4@_=b-UR
WQw3L};|l17}RiFoF?2SLGOd8aP5EY&vg6WuUn43@tv7s)mRXXKRuyq*b$P-LpBk&MeTE&tlp-e<
#ZrSxAPiW+B*cf$rtgSSgxtcOe}5B3@IFho)@vW^f&6m<n=bH^}sumTL}6z_#>rWI{;Q;Jrq231T
7IE8rV^<}~K4y)j#10Uc(996M!@T!O^aA!^J=G2>DbNGI<Egg-ixqAP)N08nN2&2deIFg6D%Hgbs
p35V<9E*|p;(Z!?%6^j*#o3P<&@9SKD5>H#HWb}iZD8HE|m-;)|?x-(Wu0JkJmHcK|BvbR1V$7JY
D^uwcwS1ADzIk!-Gi8hMk5e4n>G{d)(aF!}CvVP9-@Z9Ro0y9oJSW9OLv%2JDQAB>eK!Jp!!p02J
T!?%iU*{!qtSddM%#X5da3etQt+o+kP4LhnWg|`HO|G(|9F4${FmpiPTJ2--*9mj!h)Z&DLN6KrX
1G-^VseDev!UD{(1D`<lXrXFsMDpmJGK@s7~w=?3D^_|Ea7CalTZejiE~w^D1t(yit+!)H^7a4fI
Fs$&B%q1V&JXR^ENNJ$BoUM;BMpmR+#iCWa!cv`<rOf?g5u$Wnd~qk@^ubSqBqPf7(@wvsDu8tY8
XoG~b+s0(?|Y>jB;N~!^cgp(LA1ihZBZJezr_EsMi;ojJkq_&J03^SsfEEY(ba(r6lu&Ks6&*qfQ
x;kZ^Ydz%vfVB#!`It`VEV+zj7MS$+LB7dtS_#JtUKphgIa2C5HG9q*1Njp%Su7nGKm?a;u|o18#
qnYi9tHN`(0UH9{25#FB}#>P@SHe^^DM(SON3{{JgdX3t+m=;z*JiE*CwDa9fKo0jPuZoe?lftC;
`gZj0bN!cuRS<fZD*>pEDPs()GZZ46E`bw*L*BPF6M8%&_a0sHwl$`EQf#21kwb!N8dIv6TeL>la
@)D&8{<$k+<c$Zk8E%ZlK(MM*6{ZZ4}u!=29^k5|(l-B5X6e2inZT4H-B^qUWfU-<8UfepMUaR8G
AFnW`vxJc%5^M$+@dU&YjBIFP-iBL2}W@|;bf((P08Zc&<APA&5GDcnn`g<04iDJX^I8Hs?GqH;(
$>EyY#&Gz&OnLEfqomeUrIH*Fg3I)MXGTAyBx=mkRmlB7N2L0Z0kwgjS`;|~F60-x*he1E*<XX7k
xfdRZte<8Y3~g)0hQA!j#G2LmE<F4*Fxr&n=G_jcCXChASuEZW&1(AiE=u?X(|Ziu;6&HN80$tpg
Xh;VSV<<z8m0Cm~o=WCL_&hQh8NUOX2u|zKVAdZ*7v%P*0Jwi~&+U(qOT~qcpZC0XP(gsq}Wp^C!
@P5^|G~Y902q7r=)m^H30?O{#nK%~gMomkZoIO(4*VTvn3ob@KLIH2qjPBrH1UqrG-cM`1Xjrbyj
^?=~EYD)_mL!oZx;-7COvqAZs+gX<mLYU(odwUb4|Aq}o_G+}D#=~1BB)+*C^J=;Oq8p!Mg4M=A*
xEBa0wkTg^F5cLtzh#>IV;OshrI<o$)kQ3NB|zl5zEK)I)Q+=;fs^gX@4wX9kH<gzmy?aY75|Jc7
<mV}do!7kKM4~4>kNJR(Bx}Ee~BzGlj93e+R%qQe?dfV0S-h9@^>4fz>-QF0MhAw|KsTkHrbJGRv
5MwrRSyuHPQy(`WYGK2hXW3QNE*KE2fdy;@7#T)30<)1Eq*phQ3BU@apuZ6U?}NixJ&EB4=w22WI
=73|rz7s0Myz77;I7F^J8tN>8|lrs-);_UgM=F`2F7mg+w2(Hr)5#!Gk0+u5dIo-je@yCU*L)Kzp
oakMlJAY}uK8XpyShHN{Ueq;E92$jubbb)&JY3#+;M>7jV<I+pHHzy_x3n?m~%rW>Fp|3^B%ta^A
g!&job-!N~bG<6UGa^nC7sx|MzFIGG3a-qby82U3fARx5R|`sJ{Z+0U>d$dn)`tPC=7<v3OC}~6R
M!`HL~<f$XcC;Zp0h0W0Ow9lI^M42{+(-fp(9e$9LabkFf!FcY;u%L%G|%dBVmni`CwYJ&z!@UgI
%Grx=kNLz{md;4mz!Gqt?}N>*esb!`~Y%#78v<XXq5AlFhdk*>WCs8?*poI1eq8K`tAAsoB9^oyO
xL<P)KS*^tm>nbw376*HRPJ}1<!qk1B1JJU2f(Na|yt^yAuZ#)W(ISOBi>rxN!*d)P4YBvD2ON`t
=tzffuX`4DE5yDy;8(Npb>+}*_T+tps@rLd@EN@8S7KJ^r&Kl{zO*~y#Qf~+}P3~LOL%D+uQ5Pzw
p}>w-W31D2Y)s0##y5YF2|?p1<si$bR;TashfU7%n{)W2YS!A}8FX>YZ3_e8aoiiZQy+vp8Xr6Gs
f!x*;H(5C&7iS?+^}ukWvqC#s*QP!`>#dkOf;6DmsfC}qB=!gFW)88X>bh`C|J5gW}CexgS*)25^
LCWZH`p+>$pIh8dd*K?hf52^reguEFMgmUzIn8(pRcT9?MzSbuh4udX@Pe{)jN=E~XwkGt@L@8rG
L%OEoLV4gQ_ioGztd#&RpI0!>mls?@gd;6O#TkvFP|fUA1*_Iz~w)A9N7ds6fBY0GLmeYI;867nc
udyfDOK7heY3%<{u#%Pa>9w1RlGJTt`FmS-fsj)nfdk&Cy7<Ju|PLv)88LbxIW1pSBJR{hm<wcI|
ohQYVEOP}}RLBO!y$Y9kcmEFaO>sCXIIgKyKWMjMXmp|h2(a<d>*McFpHuRqi=F3h-;kFnd_<;KK
E4C#jxRH?{EO4Gcdw3rAv-iQ)VkmAc1g$6?Qy6%4()+?wiRRj<N3>0_u$zHv-LC-Y3%&;{MCtRs(
bKlmlZ};)uql4C&w>NaMAo0cBz&jEWpcl4=!WM<LOb8H$T2=Vcae9#hU0IBqmtI*8koSJ~3u#0PA
T?k9LEuxCT+mQPO@zcLR9U=hwX<2GPOv!x#6R4*#;9HL285&~vsGHi7krZ8rT1nK8#S6r#B^TzQ*
WYD=XeST-sU&|x_oz`0rk?RJbfncrl0gj9?<CUiau&}MU~@(yrZ4!J_gxU3T&R7exdGfnT<x7b=}
CCo5q{PxUei>u<)V~d0S{!l9^G@`Ffg^?{x$d({1VSCfZI4@iPVgdHtKxKtA#5n0qm=*?RtPqrj%
N6=gy<u4-qPqRsJDGwvS80A)Er`qwBZgsC4R>9_6EV%88j`GlooRq1;$b6{gsUBktgp4aV=|f(7a
nW^ZHDBInkgQWSJDH+^N;GPKnc2xnyNFtTI`ERVcjd56G*beAl@pS;XG)`u4R(QHVkxPC<`$iv`B
i?dTB0u6Wx+o28$ZiDHkfUdnmts28+=^PT9|Pa}W(Xeg;+=i5Oer|3y8c4sL_cq&;gY^*iD<UI$8
XV9GH^hBpj(*;pSC$;dQiewTZzh#^$ozSaDx<FF|``IU4q5l<Duor?|hc6Xk>nwOYF6Yhg7;yf16
dix}>$W={-ry8Ms9aQS8p;r{|493rB;W)*i;N1_%-|FSd=X>8i?!l?g*N*IhP>T3S=m|Bc&ehepg
_T-Ri#7rpkCAz*r2L#jc{vmz*&9>{F}w;OmbT@{LZ=Bn!|?EO@U^7$B`rQStn%~-om$)0)+sxzEm
hfIW9tP`1l>J(4T}6BDo*KnWSzxoo`6}R?oE%z=h0O>;>m^7lF$A89i$03>|0n+Q6nNOGhijv%{0
?%=ak1#ETpT+mzUw<>%o(!{fnK4cs>2k|M?BEHZAzwy&8V4GzknC*glq*m)8t(M)@uSotRI2uecg
`WPGR;aNzx*e~1|671E(du-C~5a5bc;9%7qVKHV0}^lN2K#)erF>o8y+dUO8iBtq;N2d|x&6|8l%
PM$GF%bzf-uTLoyFZg-OK5?KAV#x$~<-%NVOx9?hiMKxsi~5R|EJ^WjoG;ap27G%wj+S{`a)4DPy
F4Q})JS4Ziuyca3VO)LcFSiR^y?jKHvUOv-2dX#m~d7~4=IEM%Tm;L0>aXDT=*n^(?N=v>KgjgD~
au@7&lICnpG{V8<umfI0^?m52fJ>UzG}p-RsIk=Rg~__AI-NT?GT7I7#kJ7b@JV(!zKNZ}awIrh2
ozKTD47PQTcdOlCW_Tti50UaD;Iqd-tc#$+m7!;b!)kT^=!o}4FRj;I)|FhDY*JSv)zH!O3cxLI<
J+JhmS$j}u2DeK90@QS!n#t_FTBfCPYwkTEe73<h5O&*%O6C-U5FV>efgG%ZO<xJx5vs!+zeCIc)
y!5%);R)?{%1bl>E%`yNX+bJj3B}2Pcyxt+8ljk$m#L_-T}4IIELyCzDWDG1X-s3Cdn_F~ojz51(
DN-Sy{--eGgM)D(01Il^%+o{9ZF+0AE0N_kXs|S8S1-%i3yv5l#A}ymh%E`u*axL=IR*G=wyDDaT
i&!QV3P@@wH#6ke8B%PeIx#V@H#vdodZAUB>eM>XTY<ol{yRyxsOV%!-7dy$`9m<!z&WrIxq$GEq
pJVZ*rXcD&*0V4%{z(PVDxp1+CL+s<FVv8I`7DAi3#$8MlW4XQ#qRJLfRtNV)8ixeoW8LU8p1(7!
fB8Fk$ftSFvX&vo6LE4id<CKL#is9qB?Sr<1UbH!IK>SJivhpxq0;LmY5f0hQc{XX|mtuWb4xJL~
EW1mato8v013hmn6)Gh+M80al>4yw)K0_lu?FL3fl*|Rip+y*^SO4{MFusXM+o`R6v;%od$80A>F
w$A_Q4=p8vL2I^0M?j9FG12xQn2;9sUX?{OyHD`#o31j0FBzYYAZ;&#|L1ne#~))MxvGzj^)PV`s
`3a%W;Pqa8Ft)qJwR3k*~2FilnUg!UY&8n^q3ZYplQ2Tf~vNcUN%qVPt$DNnAvX^f7;7SEkXviSH
-LH5}4fKOwbgvRtp~z^RW8%mHf%zpC_{n9frt{v=y;(y9LvoPYoRp^K)?;KOoq&Ax?*(V}81U0DA
)O{dJk)^zUEB?~Iwe}Pen#vR9|snRAEi}Isd(jOhdNgi7}*@eq{a+(qDr7zo!TxCF%SmydXZwA_K
H_B<J!-@eEC$2pm?OyV3kPEZENk5DrQ85mH91c~|n<;+%%{~)p7QdH$8x&5e5>?BfedTC#)Huvl?
w_(<`d8?JY7>h-&YO750xuXZWAUtA#116{q=~0j?W$e9mbf}ngQ`=`lv=f2Fv%#Q1n(SkpH*E;Pi
SOS0$7D;@m>z{iM5($w>gAB7L=^tep9KD=qXv&s3@@NS$Ft5pLr?<05>q)hWLCXew#f-(XGHwa(v
gO3V-qQxk(q!jlE|-PeB-5L*v}}o$J9#Zkv|a!2X(U5=)-Z5e2CYL!Ry4uxhfjx&k3&K6-MmZiG>
{&FaWIe|`dZ<k{_!FSj<(S8;zN$UGB4WHjhpCZL*QtX;bNaHc@FAbWeF!>dZ_{e#l>=sL}y+YkV8
ZuL@xi8~WDo~x{tU8~i-+=_oFyMwRP(}phbXj*n!&EOPo=;?E#w$GZ8oA^)EfhvV?;-Yl9=q64S+
^^p2nz6Nl>?^LzI1Yb4*6x+CR>$MW%eZ>1ueYsZ7JUX1#m1!>E5(?Qw$$}KJ&O~*NKgMb`EzNRQj
%`oNVc0d9>rA~iygXEYrbE%Tp*zfPyuW$-O5LJjC>?cRNT#Jp2!8Tk@{zFkjjnwi!hPpLvTH)Hys
*Vu%PQZptv!GmtNWSl&W9Ye?LR&pOl&}jZ(Z7)5d9h7l<)GTsI5^kUU-IgK-nB@*<+sCbX42__ND
Fk+e$HyH>H>H@G9)yhpc7+DLj$A)I8KU(md~)e4dsdijbW&mt+D_>dTqQEXb+keZ!VVMoOodc~oE
=@n91C1}EOE+W`27$)MY;N6?=v0k>kz9BDOysZwFsS($J>p$iz?1(xfYqIy>KilPebLXcoU$)&Sn
Dg{n82iQbWrQ71@C&DycX{f=)+JCiXzdsWBG&-Pw1_c!`69au$ZDxbX08g1j|F61C}Xfrfepw{`8
%n{;G1CI_EotvYA1In(xS5JvyF?fqunE##{gUSM*8T7_-z-?UHwR#eUi28%`*KM7SS~u5m)HILpj
`$D#EG$^b}8Z(mP>!488}o;kPl=xBu-1Rn>9*+T+D|uNRuiZVp}(vIx0pv0u8lxIg?B;D2$kKm+r
O`))*r=5D{cGApQX`ojy7x%@$#KEr?b##!@baM%nEnn8zue5JbG@QdSfGZRI&IrbSI=FQ;Sb+u34
ybw_kw{vZD#9CofBuoy8C_<2n+r@RXEpGp4Z=$^(VLI)lXWzev-(Ki+2fxXU!A5ZGtYO{_I{p6sk
a26!!_Qb+e`#8Ul)tFND0f%v39Qx+Kfn+CqGjV1>glCYKi+a;=F!f5@9@upScbJLS(zC1OCV3KuC
|5wGew}LNl{GW7VKxtH;F_FkPr>-a|$UjhGC=_$OcIdlO4JgtusG2;}3g}0F(Ed!GMN=YFfuA;1p
@~-|>}G=P}peF}szd&Z{`R_A0@y*@H@lw14o&R0IJJ=JGCHoKd)Qr`oq%t?P}At34N-#Dr87*w?O
l(BrDT%Bt^fvVv3`$+(Yzvui%y;|X>uYn~x&-;#+I`{7MvR#L}sq&m$!<^k+iH^ZUbVb<?ZK6NS{
t^@G<?2cfC!*FVS%eCmf7PpvHQAYg?F!MQOLbod(?yrOKyJ?h0i|1KNsVyjgM4zdYMasjyy~B0Tr
ch}z<360oQJ!bxgzPTq<aI7i2p2g<B<hs*`nZSp`@#P2ieZ|JB+ChAYVY>o*iwPn6OQ#NXC?ZvU%
{%3BD^j>#CYLS*L`1g{<1Qx;spuHco^b6LX$Io<<&My67-TtxLAU_B<lx^-*rVTk!;1zD)54iKx&
$AS~#y5bi&;=N^&<vxD1{gm0YBpAW@e{o|GNx4yL%@2a(If(OfG@o0hy;&|qy??^2WMN$K8ML4B9
UWC_6p^W9PhKm0&lSWw6I1r)g6GBlBHN#Db3zGhTPZo}(KqL<q6)1*&eu#@KFV~YAFx(zVVrFgxP
oCDvf+ki6a*g=TMA%^3fh9x{|xQWCRO1p*y$Pc0Z=&_%Mlcvn!VZXtBu^SwE$`BmKAS(I<j{RZHT
51S3O6=9?={E{{b}Q>1mROoH&NrR?+R$evgQ=$BPN`w8q!$#PSgggDV3od<%)@p$PT1*aaeeCq*4
Y?;+6>o?M6E(x+9565!QVwd62}-7cuxml4C+FnT<oxg1nIKfD2*20t7bMuw^mUKQTAP2qc7?Iv|~
7v>DtB^%^6KKn)YqWDv402&3@62X^ESWBZ6%h7uuw(9hC0dHmRx($F?#0HTMOpR&awOp3ruEZW~;
CedK8?E}RYsM*-kAwhpwfI+C~^J6`DkCk6PoI6|q1qR4F%YTOAk=R}tiWg+VZ5--}^rXf=pIyx^_
^Y|#Cm<j5pUIU~eINhdpRn)r8&@KnG+tfBjZ`cCNYVaIvhm4^<3p6TXkUiF95s!;(VTb5(!qjdIO
pc^XOX6sNAR)&Mrc+=#dBhqjE0&obc33=Yt&k@Yat=fntAL%&nZOa-5j{Ni#V%19h{Fj1!V!+?8(
Ggg@sDg9AQjvARhCgkII;<HBMbK(%M!a6H71|S(jlM4;MWUNW1!)LO;N3t1KLQ5nr=#lFY1Mg!Ye
WS$PGxMEQ*DkMAc<AepK5~DHbgPDP560+{1E2+1hsAEep#a)&zhI%*bZ!e6>v3(!E*RmWiQ7t0AF
3pO!lp1=oIg&7Gp^;Y+e_QT~t&`3C^{9Tj<77Nfz&(TaIjPboQwk^yp~_ED&#f+(jO78P*^gt7-9
Cs5DI|Fp)<w$Z4Wp30(_->7s06daJY2Y#{w=Mlc+_mW*M+KXQ7xFnW{;=0lf(S#CsYl87sxB&Usj
<S!GDWkD2YPnri53#lZx_iP#(riRSsB1|Lzub~ix0A`U9SJ5%rd}d)=xrp_LVFcr04KB@L&iMTcM
|keN9wm;0K)?$fJlw=Tw=c-F`yC1mmfwPGU$k7BGFqbJ9@|VVqb@6Mv>%2Q793fYM&hkN7WUeA8(
<_gTx@BlpL_ifw}C4@fEq_(j}u<?*Jc+7uHUE?3{CwMcOKj<3_V7o!wZ4eTQO9fFt2d7Pmbz>!lk
7Wqj6X`YoxRh+)ko6XY1<eu<4EIn_b4-x<RaW*&02TJ5S85U(qFfJVrxqiHm|oJ8y<f<aspV;;rH
>h_0{ysq1*iPEq>tVO*$maKdAtru@j;Pke4sZm>+;|e2;9AAW|N7n29#{5Vs5R_b;NyIhWY*m)_v
PX7x;>^v%Rm~yW6`EKjl`!(61=xmb?qxnxjdGj|x*vVuh9=OSfb2Bb*mmHbYr<x!1Z*?5(p=qZQI
1kjwo9u@ODK`qala5j_YFBY2wVgphZ#-SgCdM*<M_?#ZK=~p+dH=r%$9kfLWb(paTsRMb8fS4lac
qrsfj(YbI)A%^Rix7`yJXXE3B+cY_c74)~~a7ln|a;otIXE&8{9RlJy)QmCc@K(`<2$;zr*##^OY
5Y(+7?$+8?vH2oHJfPx#m4h7gxi)22HRuUMS^F}C#rj_L2i)PY#+iwm-NK-$k=_n9>Es4u-26Ksr
c7Wy>5xQN?=23E;TG=ezHi^*70sI@Ay|8hcXB$(pgZted+j05)P_EEvrt{X3rjX5C(At=6M)GLoH
>OU=MMNbF*mlA75^p}>;p=zEQlGsOBJMk7-b9qbf#Oro=FD_H*7iL#SH*E+6i{vNW8S!#^R%<0xb
_J%iOj}&$MUL;PCJ)8eL2RXo!gPG%<?{2)<};cq9zk7wPP7ftV94%z$&nloAO3ShKVf<00~i0a1u
cJ?QvIZ$a9xr2n}>EI=e|0u+tHnQljNBbW6XIc{WRyXKcwUGcd<)!}?s#WeU%2iw(o~Rh?bj*_Uh
!b8zWQ^!f}UR}fvhK_&!V{6hVfh>hKKNzfuj=*ae$F)B$mFI62^mB1y(GPV&+WkGR1><dQK78xnk
W#2*b$_j>I!r~VDR8^QcD)z*f)D@ycDo~{QXs@hd##`w_#z1M;Kt-EvYr@74hSjCDId_Q;R+g7Q*
<%itW7pFbzt#O{t7%<F&RljxXtF_g4Lq3eksB0$tSsg>ZyA17mPUCB3)d*FFLp?$y5{|?n67=V%{
D8`{9eIMmM!b7u#0&un@}w;yO%{(ezukrO~iq`3~fzv`S$m{F?HlKSyAIvOZzn`pQa`|GgbI7+5d
E|;UjAh1lqdta}_oNBiObdKFGDf8GAgUlnE`-@n<8N@eivz3w0l8P-(KHDbHJ-A5BuD9Z7;pHH9P
fp|P=9%*b4~7P=MF<5n>cbV}!nJg{Z@JP-tD3r)@^@*wBs7YJ^sPK)GLmo&60i%?}`Ijz1ZBXdn6
ZgE&SD(!1oSg|!lX=j<z<!&Vglk*_AWE&XQY#B?XQ@!iz1v>7fQ716gsihnN9v!KT?q(~$>NO$ZL
^icrt*d1Dh@;wqLZ?{OJfCz+duBE-yB)7_!qgbVBv??0^4|ak+IzUZ4c3O$i%pi+z~gtdb$&H%C<
phbw9QvRA8WLp7Ev+;soa7wOy$(^8hqN50-%I9;dqEykI1gZd&VY4)mbf#k)Y`ZzWuBELCZL+qvY
y~ccf9s@s0Sc?jC&3%!9Ko4x%+{Z_p7+eocC~u_jKtR1+U=swu$eSHY*QjsjM{3V^k>*e08Y`Qqp
EM=VmB7Swy?!?UmCODNo}y%)B4P}39}qErv&_u3@tYKvD%7@G3(*XnrFTE+Mvc+~08G}dPMRlz$s
vf=}$4ew^OE-sBqKcrHS9=U-7)b$>5v+~(>I%h>axmfx)oI<>-Rr^Dy8M&tEt8p1O@imcGn0mRn&
ngnSD~@P=O81h+5nF3xKD|))(3Db~I65tkx*E!*>p3g8H8Y@E$*1+Fp}k%@xQSOk&@qBMt*aAY#;
>E&_2$fsQ%qStg*c5HJ)mrC61om!&dR>`vKCQ#B2KYJEi?^RqzPc&Fqc`PCG1ya6NX-_d@V|!7?O
rHnV_ghA8F`(hbU#F`Dt_+lill4Fc8Vzjo6?r!2H+?S}1FnAlRxgYoxQe6VukTt2@>W53ELq9Mb`
{T#cG(zkVlZ5L$}G2EqMIzha%CXb~HgX_RMk)_<r0VFHWU+ycMi^lIUsaQ+Nh)4nDfs#>G&az;5~
r@DthzuOts-m>vsa7lM#*iDc2=>Y^!gKlR{vlLJ+m5kJQn5vy*T4-T(d-r-(WKyiCuSD^SeHnV>4
y3=;<-6g{9m`Hmx0Qd)tz-@?NyL;SW;s_8Ab?X27Rfc+5m2<Ow(`W`2!q$t>@u3>VMB0vG@>_{w9
m{j$<Y8UO7V6b-(tR&vE!XXj|XCcHVmrcOgUa#9rm&$z|m2<w{7Zd%&Zn;+A_|e%}KPUpYAzzHv0
!)a1G;Dm}F@);KXSh1#X&L&M*wg$FK7MYEIf?q|&5Ey(E8NW$}V#ICCq)or5GF<5dd=DkMYSTn8*
^%j-1Zl!US*$_3N%HNnKzhr!>HX94+TVpt}1ZJP$&9=m+AdYv6GVEg8A99Z*#$u`=63<){aM;9qz
R&jH+oCcgO@=C0pCQCBDGBbX7AE!x#bH(%UdO3wz!tm&}0oukGR)Bf&;x?MnGa!~lBrad*S3<+Sq
d<EEmuCqY6j`a!<X)>-ASp^XQZqsqgZw6i=l5~Pxpik*4*llIH7q~S@3cTi5WekZ&$gLdw_&^jgc
bE+Mxk?SzI=cD`ebx=`d=7#d9U~Q;P4`Sefnnf`uO}gW`*osq;GzFJ$nAbF=ejoJv!hA@7|xjK7R
kp=+()a@6Uh0SC9F{*~#;_Z(g{sdi&pAr116p_}MGy?D*x$`7iMJVE-ch;m4ORp|hW#ot|UKE;Rq
{{mJ?JlM{S;_RH&MZ(mUp9rJ>kkqQTx#Pak_>3O$DJ;DG=kB?uSe*fm=h4cI|t<0;p&;NG*%e#}&
>6@RR)C;zVFpqyadH?MA{PcA|jHP)lEi$;w;~(EVfBPB+eRf9gXurODdv<z$`u5G}?A2T9Io#{8_
t73YU>v~z==TBNAHnkj`2Ou7rm}zsy>HR@`Q+#G_s1g{c4&Jvb?K)^KYR4EPd|_7=YW15(+~OH_{
Z6|P5kM0<o~Yx-;@9M<o|v7|B?KEAel~-UGwO2nM^06d6p-*k4DJH=zM|7CLX=WzrhJv#_-0MvCD
IHD1Lm4ml=4LxVe+?ML8o38ITxz8deaQ;(G@*<>~#yhe6Nns6x4<YIGlajthf?T<z&2HaA44+-~s
X30LtVSOWVMYrg;oKb{?*;g+lhCzl;h(R%IGCk{3co{&p76f(x-d2W|P|0>6~?Dg5R7Ke5aYfrqy
T1$5#N`j8okV(pyYlf64PtnmRNt0qU3ek4l4Liek&(o`RlFmsG!k6AFn5w&S^b|$}pt!n<7u7HG5
qTb3CQLXKyzD0*A{vY5K%sl%u<d4CzJlwL%&OGefvPw34L_v0vSvv|EV8YEDC%eo^NG=!gwlPYfv
y~cd;@-$1)t(Yrs7ty<s&ReyLuiie;#NY(<?>Jz+9#pX@~>C(~nm~r0+(>nz++aOo<I`3N^s)7(T
c!I|_zoN$i*f-L<c^=Lzkj!$$B=XmA~Zg#M#{2ISF!)x$m7-3Rc?MV>~(bu6w$vRyu>%*5j~2Od@
MJ;j3d+&M>p*Txer*RQ}K3yclBmw6n2tm^~$YH|gw&{CMC@}BrWdiqp=!_B)(OJP52dau}_W<(hL
rN<m=X<42K7`6m_>xhf{NVj%evN&o^>fNovI0CExRu+OL?Y|S~-Ih@Q1}2rSW-^+ax{=r{kKN@8@
7QnJd~}$h-L!cCLwD0d>8Dscg-<0DyvaQtO$OUl8=l1%AtsuvR+%J08&99sT^dpk)e5mnB7>lr!7
&0SARIC94o{lJvii0KPahmU^i#r^zhc*N3)iU_8f|`n4NSdDbRsFLCxFnSJPi!+#=m4H?wTgU%Aw
G3YgV$xiqS^Tn>I{i0Ck6D9EGP2mPU8gr=d*{913ihhaY&}{n~S$hF`Y{r<|sj*uIcT0$b!s1pfA
OnZ=NqC?OZS+#NEJel>n^#0C6!Od}N)ad+ozUf|`kj-sdLNgP-SWX$)VG5Cm6vy8+D4VWszV3P6L
+?)wMI3=HW7IHa_3W%Un%4_U+>eD@<%*0H~dM7h6(=zY45A||tTSzIG8UR~Nw$FIcdzG!wK;JsHV
fp2?RThpBN9|4~b5Jr}&Kw?}r-0@{72&XPQ|Q7p_eQndBu|#`pYrQ)NBz&Wh@8gJ6$$`ZMLJyJe$
;F$hk<3DT2QDXCr+fss_Wa4nYQY%QEQrkR0T&)F1)LnJ5QQgnJLwaCsf{*t1@CGYUkrbCGy-;?3I
IdnpP|ROysOvQKCv_0PN<76v5leY^pXi9SR<@Vd4#b$y|p2+HR8g{U^-8Rp7b*%EEBk0NqC$F<YZ
`GjNm}|A!#D!quZci>zkH5R?z9(HSFSxEPJVYL$<P(rlr1IilAd(3=OUyd_pzE~hP1+qINc2)U-;
NMh$H97P0KV|Q=`6);WMw$s{fYL-X8y^A&!#er;JT+tY7vh`JLh}2tI2>RIV*Mko?y&ziHeFW%(X
hq^$cMbe%2;b*o*!m^df(WlYKkCV_^jjjuCEf&{t}f#dF)$@QrHZ%leM5=ICN8H@cILroaZ@<kI-
KE|ofDX^81yaPWLO>T(qo@5qe-AyXyQM7zS$YDI$#tR`hr-kMSrcfsVR!?5z?5Z#9bIM{q%)qm_8
uXlOwwde(iNP=}nd(&CTVGgewOe?Y2=Nzrs{d`{oDyruWjb1hb)I#u`jzVJEDJ-$+gSfJbSC?u;%
}*1oKGE-_NdFEs1v0Noc{v@&R+^*)PU;A~WS$aguT1*Zk{ke6XgJ_;ZSNt}QR-5{0F<Enm*F#>Rj
{0o4R*0R75ka$bQi`A(tkQWhQMfH&3{2MX+5G&mKfPsyLEx=47ihI5`4k!bLMLbeMSy;X@X$Ga+5
+5%RW?nnys%IBf@E~3tf<RNcUujgX`lzC@@@)_?M*hu=-(WONu2X`bY7E9vy0>vORG6P)r1YP3D-
T=$z8TzlJN{nLd@Rw}w8@d$D0vDUMO2uXyn=XPgM)iK1#U}3{2u46hWj6Q`J0SqadDGPtQpYF;Yf
{*M*r#GHhR>DsTs6_Pfo9RXX2}RZs}xwyoFi}Ta{HI&#$Jsrv!>#_({U=4YSzmG^*62g8g*<5VSR
sRdMvI4>(n?`k<>ksH941l~t!|2a$RMU2Ms*jjc~2%oolAiN8l&k^G*5I4ttQ*BIa9#RP!J8|kOg
lpV#RnrGRj?GptScwBKxud1ME0;sJKQCD?L)4gg^?@Nu-eh4SJnd8A7Za26`IJjQt-#xl-w;Nrz2
6Uf#e`w_#WpyQu=r#T&khpDZWn#a6Y!yS>(50asqE{m(L<oq4c+*TB@jE509QqXgtinRF$w*(Nr=
f_MWNXo6|3B^polM!phy61rL@e7jKmPNZXX30y+B=H*Lxvh+<DmjJElgTjas`AzAVc7W1JI-3c))
DHf^kD4Ot--Vz?f__#W)3H{NT`peTY)au@6i9U~|^F)&c-Qf1Rb-_b{-p>B3mp=rbNc9>*UmydTL
(iWop1KRIaLN8^Gr0I;D7T4nlb%M#ODj#2LNiZ)BRYp-mzg4&9HF0tP%Tqq%slw|brGU~B0uHmHJ
6nGf9NX4I|n1Rk)bdfLxYH!{22puhy%kujSykE{O;$#dTDGog>0g;DB8NMtdpIw{D#!@A%Z+wV%E
e>2veRme-Vv~pQ#0;rAD1^_|_p5JkN(8lB?1MXK=Vs?G^%qlBtsm6*n|#=^Y_(_*CZx|ez)PqPHI
-cX##g2i87JvXnl#H$cIUM=)L&FmF#BQ4*=0|xhO69&>|SeI@yAN|HY&17rfONT<*wamt0b6KT})
c-J*`|&HSdxTxMuyY%3_}__c<n82*a=}ME<p`$Stibql~(4t3j}`0P3OJUgKYa#fO{6qiHjv@nH=
XuaUz`jrr)ZW=SymTFJVu8I%q2)~&;)rIuzl=wI>B`)K&6!%g~HUxXzw<>PSswXLF<s;z3#Wvgpz
6lauFU9ESkwnHJ|O^GucO8wEnAE`+}#%=wAuMBCdT}llLEpu%Lj7mVvD2d=kC@2iF#k@i1{^W4D?
uc2d5He{zwgR5)90q))K4sHV*kWf{SzJ?_WS*_*<R)79c`(pD<4&;*`?dr)RTD#-?nXrQJE>wRDl
1glB9@FcG#izNRi}b4q;-3ZjXSGDv7L)Hr-b4h1Iw#HhjJtU!jRGC7JIu}-Ohgh@blW~Rkw54@Ak
H7s79t-yL%-~A>gDHp3u3H0pVnX`mUqO!>N*y&~=_#d`I2AyJ_E)tuSLU{7dUdSE^wJ{R7mgv5EE
hGKZ#pde@KE@Mos{)3tk(yisB{Z{45)QIvK)QFa=9Vh)uJ^nuyUfzNtUZYQh7Er^VLqq5$Q+=Xjv
W7+z9`$}j+gL?MssubfJ!_qk|{57cX=GXvzyS1aL`u&ZpP3df+^XQK-HZl;oZ^mp@=#zv|V(~U2$
pdP6eP(ALM!V~=)EakVOQ=JO+N-9H5hnDSW`(~*PoLU1Kvlq`N}CTz9+AGglLMu`4zmH$cz2uAch
PN@uJ}6YQTJasy53f!>#Z4G?@Nzv?ZM`{kmyB3Tj>M7G%$WX1AMh1zd4$jhK}zD*8)+yS7%&ZXZ}
LN!jTvy!k?3&+=hd_{#G$*cup7?B=kflZm1RPHRyJ<@i`N88eX@_MOgZ*#t9{PbXy1rYlgy8{H(q
WJGRws^RM4K+Z4xbGyAN4GFwON)H&cBr!L)mYO6{=SJb1Hkhf;PCQ+uMH)IXtsQpbaz~9jZC6%v`
vB$l|0V*JRTIyx<;aSxHfBPc`C__nFyNp*Er|FHO*~UZjgPyijZ+!;LWHKK<YmK*_f#}LN%^+Wlg
Cj>B->TDdIb(hjB-;=@WY9irF30@zhYfsm1uu(;I@A*wz-)%w)h7(!%(~iO+P?IMEf`$`{0)?cVU
uhLn?D1W&w$DH@JKemVhcWj!9=5LIos|33Bawh`nBY$?Wk{+^yb#wDDkgRBYY9H8Q-;Td-zmMXua
(2DYRALb$V2V3^cOcz}IGPxaF{5*QtV8E&l&8<&Uk)c~Xn|#1I?>t@W_NJ6<gKv{Fa&IeIHOqR>?
=l9<c2XH%U%2y0iw1uUUJt91DW%;?(tzS3~nCPJO1wqZj+arW~H;MXW_tI5x1U2RQse+{~i*0yJP
s#eu4ho_&HZ!5hLlx9c6uX>oSl3NQ--nFoMHLEVoDeMLZ!^x}S?U-BnLH{bZ$n({_55wPuYQyT-{
4r*f#8xo|PeqaHJvm-3*ebxe>@5)zbJtxl)rtUrbRJD$zA~~pS4U`2W;>}leAWfM$5^-o=lhexH9
J)1xc)3!uZ@c?b3BME6yWq*&7nV`B#RAO8{Q0Zk}mDcGZhnQ$ta&3>CT>LxUcnxL4PS#rKKi|#{B
Z^DIy~28Pt>ApnmB*BvezP({S1@GMV@O=T4E<algicNiWc&Is*j>3t(-Htqj(j%2hkbt%3*Fj04>
9JeyF;PiDF-24YOpS4K6v0jZWvZ-ah1EL9uHB-08@S7pspdTR`iTJ)}>u5EfzPrWQMRNe_yXUoyi
24QWz$AR6f?Rc<NtG=f~jV)G%=B3O@P)RxzicBTu+$sA{yVhGA;Kmr0v87WU>X=k!4o98)ZU_Fkx
xCrz&NofW`$6d0HIgSuBbZ0YB5zW5Gjb-jE$!q^Tw1V3?$0&Nq>!Fqkrf;?dpQe<g3~=@lRBl4a#
UPpePvTYC@w~WAtf?)W=l7s%t40~@2$ywH0+p{l_`|<yxqP%8@=5lHH@}n6YA7<BkQbRxsct2948
fj{SK|=L)&gkNATAmbX5k9K~QN0Ebkz^kYKm(IVM1$uw!?bUKts@g0$nzR0C+&yU8|=w2Vz{Gf64
QZ#fp+BDo%M=u#^p-23F(<TrH_8p5%dvAt<D&4TAALH;qG#zn>{uwK3kqQ#7Zz`b9lnEx<O0PUYm
V@lW){`%{sd~CJQ>hyX+3G-U5`Kq|dDE^)v4m`yegTMaTXmdz842pvR`b?}iNz<I`(MZ<X{3e-8a
JBBYtxHTJ1U)D7PWRVeFH-m*j2af$d#nl&X8rmro8-6V@dD#4(tLt<877w@(^pQtD<OGi7b&Iw!t
7Mgf(9D4!WqYA5pvV3K(h3<IPl#m%<(%6Iyj3L*OKujq0rUWF=eG+p{qoJVU_{`IE|X}qNVg0<Er
8g!BmPjls_z6eB=mloHqp{-L(na_%vu=UEb4Mgw@w<5Z(ST%PDjyNBX37Q+XdLS|SBbjDmkGLC(i
Wdco_2bI#0x+eIs5%-(`g0`G330#mq{<So1uu>G<)mu#rF7(JB}oaJcqJXvudSB?uvasO#mqmOaQ
%~CQS74`M&9M%phsW`3}SV1zXA=<~O1i&NW4$KYSpi!Zukj+OE{4tNN)k&kV@v<HVTP^O-?1)wi(
GW$u9P`JHZ<6>*Zv+OpZ52IewSdF8*nwY!O;TWpFK`8+vFmt3U(>7w%cMTS>hMQAr7@}Q(2n1i%q
V;z1>03$K-j#|UofD7e9Tw5RpoNNx=0DWSRTW+=YhQXiE_bm?(1`fbrd#n3BXx!*hSiH%M^ncfpF
2`k5mZr0Ao(tPP?<$**^?sWCxG=IljUun^DkhAMOR1>hpR@hV-=h2dW8J=qU#b#&47t0u}__UOKR
JKODb$JNog>>G|2{-O2mWYjkqMOSBI37Ca30+R!79{O{zAb4jED$bYtA1a0C*RJ4dTJwmn}{D^@j
RrXs<2t)?)xYMB57bh>@zJEP>_V&#Q#obe<I+2rL9#3zRoYM&KlYE|}ap^(Vev-zh12ErjC|`BcZ
Fw4ur_pUPo;r<9gXJ736X22i6h<GH9^&3AwY#WncTw5yqN?3Rb-Pm}kJmTu2*%O$${#2tI`+p@s=
FxFU6{Jo$xa!F)ftSLh{+W@Z{x>-`p~B2vy=fDqfGAx-Tn|yc78y9%~FyjBbA|3r_ub)ij3_fFQ#
O9$+b?`LfhQ_Mp0h-T<SWWRD?f=8khH22E`?;@`3wNUsYx!Y*FHH({v1fE&5)1$Pw)*C9@rfjB_g
yP^g?6QtD2kD-(odqD_Jh&5b|ey!ewOG^d={G&o;{$Z#8Avx8oLICQ$E_ye9`z|Sd&rlV5jaUTVe
ewzVR*_S|ZSa!X2I_R$NfI(l=0loaJ4oX6(UragrQx^uQ;kd&LiFi=yh>jBZcmOLhRN<Ue8B>$O(
vI?RoSM*^K<?YwJa6C4__7;QSY(S8`d}4smgktmi>*RU5?k3^6e@p&M}=e$;oP32-_9v%y({J%Qw
2%pmR){`#}r{O(tH~#OqibmDSv?{G>x@NzM)*Bm=S(+x=aD1+O~9p;H;60Zcmd-pleB-w^3q{c}$
b^;}Iv1LO(8@Az5O-_w5id_@vE~q4d2vXB~aek@Qs&8ALRhI2p;Y0+(O~1lb|mO}p;CPSKn;e}7Z
{Tf}E;eTW&d+G*3RM9SI6?SdN{Mp#nvuKS|R>m|8=ktdYlw-KbF)tx0%6D(BXg>n&DJ}PC9k64dU
gt;V8O)TB0rKtetCOEd$tqkDl``5?kKfXUHZFU)oRm&M7XMbWQqxGl%X=XWBbJn~rbD$={le^7MX
n)D+#2F@&)Mb`QcVN;<l(h)7z3Ov&)#h{9E`cplFj7Fct>B=9cA2TI-^XrV+RsTGVJFj|Boeg$xt
LZ&EK`4znq&iJ>>Ti2pNs=1;t4Onk(=m1vQ1Iiz2B@<C79~LE9xgt69}_N#zknUb7_viU&`86-nA
57u6~7~2{;et(`Xz+4-au(P&AL{UQz&WrLom=G%En3PHDxHYf}HJEyjlj=)j5z1I*H}Y;_ae#(@%
jZP`hs6u=G|oN-~@s_3N0f=N`*kQ5ejC_S5vu$L$z#F9Z>pBswcsB8jnKz;!bAfPe)BL?e5gr+7z
tj$I@Fsu;<j_2$hoW>Rv2e}Btm}x+@W~I(WNj$ob$qRX<{cIy{KzL19_Pa$^kji7$E}iR`34})y;
wg)hJK{ZKvd;a2FoKERMT?2`Ozi~V9FQIiY@%90WPR}XXO$c;3{u%un8J>HX*V^_gQ%t2uTRc?01
nK?D4sM>!3S`NKX7w(0Pbv)K9gBl-X4Uau)0OA6LR1p@r?0#GDgQ*m5>9+%#)M!nn3XIyUAoGc*u
neB4TGFei-r}PLpnF9f<_ct1_cwk`PML4mF6Uj<K#n5QZjfZ9K9^Am4@&9o>KcFHX)*UY$HYcL-3
$%9KVTv`nv(G>$vSyY{h}hub8+8&PIw%{JgrZgKN*7lY2Qb^^3SR?7yjw(3J;BXC`la)<o9EomZ2
u(6-hEK4u-`eGTgz7938IUdDfjyTPh$35GcR@8)HeoR)W<a`)9sWQJadO>6nKVf0gqv+TLr_|CFQ
l!==Zeax!!LEoe^PqLlZ$H7?c5s#%+J&SHTIcq{`)07h&<;WCX%K#*zzwSgg(v_n7zB27G0ZIe5Z
`zgSvEmhN$QnpmZ|K>HalYD5^#Kr<bDLQ*%a5Q?p6B~b3Y};N(X+KF%7dT7#42EX+r>8LfpymJzz
{5=3u_u+h10^&G~`a0-6R4-F+H)nU)wW6rs9fqf)#|B$y6*oK2hoj7>*YZY9PHvah^fUmnB0Q{$5
C1s4ESR1S&--vm{PvqtccI^aUhpc}W89mXt~jPA)g83&9pc&T%{<6RzH)jMps*Y236R;H=$nx?uN
nlg*gG=TV&%tL2gnyRj~7<x@{AOg`2+Q-vG8vr1JTr-e&UG;8d-qqZUoApskp{rOZ*<Q{u183;+L
OE*q3*Ipg+TAOA+mIqO<OO}u-n%NDYZiucs`YKwyeT7Vd^r)OMQTzuiW9L7&L%hpuF-)d50&`l--
eP-R;yr%oS+sI=aEb)ExD>05Dj%i7u7l{=6*NWLCsk;nPig|*p&(KQCkV`wtlx1bc*{K=n6y1MS$
OK$X7Q5cv8yK5cBTha~!|(+!dQtlYQg?qhOL;Q630n_^|znzDDR{+96S-Tsk?2x1Z{lo`Vj>!cCg
vj&^}sbdWA20Tw;xgwC?CN>4k@*w+x#Lbq7|&0B;0tMY%K#t;j&^^+wWh!dOXk%CW<bbVXqk+^qh
z0tPqLs<bP6t>guG>J5K@q<@uk`*D114)tY(}RbuLnsUcji>jG^wTh%D|q3aak&DukSMlaO_!J%B
tPnTyGGy|+|ee-Yq;n-!gOQK1z{EdTQi-C`UgZZ#V6qfp=J%9AqK&C3#&EExR$Gf8n5}LaSQKnC#
prvJ>}j9!=ean%rm|p1+>irg#t+1C=$}d?05{f#F&ED!v)5I!TUQ*lSX0Gxw%ws6BpTC&ewX^z{0
UiM7arh*tu+x#WJm6Dl9@#Lzbj7iraJ)OkvoeDkSglih53@CZ%9fHtFS)WyD3=X?zz_DsAHA9StF
Mpp&<6Vr={a&nUMHPoqyfJ696n;gPieALih*!Y_^K5)VXO5}QJoSjg$P%}y41#XA?(oSP+buAtgx
#a6=;!h(<S>S!9xE+-M$zVzug9Mg?K-|UE?okr)B#Bjh+A`NtJmtA2tf;hssTTCM-8Eowc$FA@tU
(RNT?0}hFE1QmbjqD-Mpi8%kNFo#%h)dds6CQI9&|J+MtqUdqTLZOCZnzU=bR*wT8OxoM5ZP^aTw
2egDHZnUJmVngribllG6@H=`h4A^8+gbALXr3V$-7s_&rd9aUK`2g(Sp6U)n2LP)4Aj*;q|a;xZF
CuN1RifQ3j`9LiR;Yqw?6=PaqkoF<?sQ)tnw_6|UEwNPVS|GuuV%3hN7y@0#!}F(<Dqb5$r?)81`
-QKkvlCb2w|10lXA#ncDb88yd(t*>GdCpIslKr&Vw0q0+)6rYn7-)m>tv>o5OT$CbuhBMg2S`5{(
N8-$Hx?Z2z23c)l95yv2Y}=G_iNP2ycE0=StFM9|PL5xkybs_bYh@05oeqDZ*FT-SKRbQ<#=L)Qy
?pcb#mO1Jvb4E`{!KlUI9-CQj?8$)pq#vO3jGO8a)C_K<Tq_5@`{_3;&gl5vhDzHIKY?3Zdud;8H
l4Y{Lr)(=vomk(j;?~9t1L_Yb7xPkoZCS;A;IZ#&9oems&te4=n01%xT&bATZrW>6rem<nJesg5y
-M5dB@r-%s-QPAh_G#dpn;!!AB~e|r4NUAh@gJ&C3xjiu<++*Xf;duQKi{Z!={SKl8@_@)8ZuFka
C!V&Vrc5uWac03|1mN$k-s|ThpqnC8o=R2iZbZ1lx4nXnq)8`f<e-6t)hkypzZ}gQ>x6kj)Hm9#X
W8v^KzbjSsf4)AW>q2I}QlK$Hb4W6S&A-6&lt(D~ZZe?JSG{_xDeHyLJ1A15XH!A~E&zLD?|v_A7
#4?%Y|AnY|15*0X7C?DSmL#;ttz9^<?VsXq})^5uPXCOJ~=K{e3IK-Tp04|-ib2D!h-?7q2I&xF0
l?;$hd_2g`H-#gYT^_8qIahE@GNHn-&cEy<zF1OU=jQXsl@tSUBSe0Z%yeBT?cxt;%Cgm|jg=`i_
dEKJ^ru9CU~FwU;#3;e(?Cq)?u8`AN5dY__RxwbiZQ{iHPz4W*S5qvuhL&L)aJaj1S3aVK1DD`go
HWd87}sgUble_H8JK2i5izm7igI$Exglx!Pnc6H6}hMEdmnpIUmlLz)fk)FRo<=bA~@*RLu{=0e3
@r{QfOA3Qd*9PRW;cQH3&Mobq!tP2eZxOgCK(wIU_R1b{g;kKh`0Wn;3)BaTLob~d=Wuqu`TkV}=
QGcyt82b;FF{A%<<5<LHrFz+yl>+}VC*M!?Nv$@PgQWc?QOn`h5><Ol*S7u5t!9Vs~lUiyeSy%Cu
Me>Eq$=10srm{hw3=v<9#~^_R_spsbQYQzqWNUk#l=+7zT^IKpZ%E^MY5uQD--C=h;m}`8Y}F89F
N9O|Wo)b+#1zpiP$L(Cq~pA~Rn@141>vJav@Zd}mE}vvRN6#1(|Y9<OS*y`kOkk0LbJo!(!dDYaR
&42TjNdgp2jyNr@A=WOPfhn}SjzZ{66=&;I4hAqlb!<8Z_W($1ap03FLzsf(Ur)4o??<bFv>yfcm
vrYK?ku;RmtZ3Sge48t)DR)k)L}@Ot)Hm65g4Xs%{Kkc@>AO55Zig=?A1oM`T`^sAjYdYV66Q=ma
J0Iw1qGV54$bVaY-v^{j}W$1>nmF(+k}AZ1vHzjtOT%<84&AEk4olVW>jL-GIYUCPb=_8;|syI4B
9=d;K|#Vw{imWu{tArUf^NK!e^9yG-jYI0GzvC7{vRdaZgKoW8nR>cI=3iby|UB<2uLqEPd5h6kv
3GfDG&T&>rYA%h-KD835rWaYP#FJN7~$Uy&fc$(F!tUn)6*9v)f75XO3o^(6@S63C)UGS&(m6Rbo
`x!F3Lq+s~#6k$teDb#4=ZQmkv&qP357!n(lQ$Kz-aUO7JkI`evt!%HvElpOX<<`zKC7VBuk0HK>
BhVQ-X&2?ifTuh(D9PsOm8Nj@z|;m9zF}1v-W9N<0r7J+9t)iLNWjHYWgjA3Yq|_jMtZrLk*ygPI
|??%f+A!_K{xnlNkLa6QM%$ylNZ^1jvru{*&Xm~`;UT|HhAFnX5#dOH?!=egjNlNjX)CU8%7_@UE
ii)iGC(&jHjDzPCT88IY4wDT9yc_3acVdM6EDIsy*G{jEa`i;s|)ihIjc1L!%)hK@ljEGn|a<2?4
=p#T0c%cu_+72kjo5f=x1gA?oAIol@YS@g6RJQ?=~}xz+e1A9ig-qJ`}a9eW?K+^I63GUSZ0ixf1
}eT8WyHMEgwb**@~Qj=Vm?1UD0m#5x&_ey4Cm5d{~hS`5|Cm>TyQmNPXXKx!?vHiMgf!xYQRc5_q
N)H?$?U9j;PF&I&CBwozx{XIsK0<Z}Eenl#q3O=y_^`r6(IKZynXIgtY>xZDOe3F96Vz~**~JP=+
A>*bG#m<n28J3W?A77nf~Al5m$sgt+z9grd7F9z$l&~ZJ6pq&kSB|Oc>F<QzG~E|2+g2*sP)CRHR
p3LU;J4JfZ3S<<{MT=86iyD2Cf7$1=ortLKhdF7lMjit6)n`S0gfs8A-DM#Fx*09-TcueuW_}Usb
qkX#tLXV1Bc2qMF)B_4h^<{Z!(RJ6y+@pu-|Yg6S<0!AB#ueI3yj9F4Tc0(z_g!&ZbWiJ&|8@BbT
+xQ!M
