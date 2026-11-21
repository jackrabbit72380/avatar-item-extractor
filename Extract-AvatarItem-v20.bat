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
%PY% "%BOOT%" "%~f0" "%CACHE%" --obj --out "%OUT%" --root "%~dp0"
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
c-rlKi+0;avf!^^l=TFRNSdT%Sz#>SE8B9Sd;L0=l1YZ*G7t$#ut|VJfRgA;_S?5!{RBYLiD%C4*
>x0&1o~NBU0qdOkKcBp+o*^ZqgkBawCAgx{?1o_dAQ6M4=<DSVVvFu^Hp(^rF$3Y#SZ@WA|7XxIN
(~r3_efuAX^qeb`>1c!{a=Ui+9oZW4p-4L6R0(@b=k%wV{FZ{3gi*_$hAUV3y>0l3oYXB>fm%Wea
+^_aeAW;=4Y5nL`^vUSx|n58`Ni6GYfD{0^dv^q1iL`}Yse&fh-^##vfKNg6MLyPGVJgV#8y;BuN
l^)Q(PdkyR}3dT233di~C??1Q3*=!CC=keqsrJ{LolT9Z$qA0jbiWc@BPXdBV@Fpv6@YPMch@rpb
bP`;~!S#|F2ribrPIo^@3Yf=qn%&U^FH)G)EGmLzHlN0`I4z*$<w}4Q94{A95RMm75$6vXnk}x7H
=(6Go?gK~=Gg)vdy(G9X%c;%2Or}_8c!eIM>DCEH=4m+Qrr;4U}C|97H9#052l~)VMz({0sNDd4B
QnDS~S(*NyX|tg_jKU*U>b7mQAp9cKIQg!Pho?z^0#P=~c3r!R(@I0B~N=Q1Y8(K8I)6cHbHp%no
1E!r2QohpFJpD1`;ly{(dXI?01>ckgj<8!w7v47l(x==BcvgJO|H>Gc#IgfHWns?qK3^{~YLqx}Z
W{9TqOMUtgCtlKOmR0YsHJALya$YF4CGe|Q=D!?`99hdnkxn3^fzM1tbj&gXCU!>jk<8Om#nn9`i
AY9G?{N47Wt~^>bgH9X9%HKZGbb`z1BQ^@?ah=@4aI-W9>`4ni{n_P33Mc?*1yG4nL_O%P9h?J*7
%t;zu}GlOJYKXA0`Wb(h@sU4hKkU@9`54g`UVjv&n{8~uZC3w_&U#WMm<`WkMT4vvNQ;33AmF-jQ
|jJvWV`2BALbQ0I^_pIi=ljk!rZeuE+7lfUI$l#xX39ZgUqtCTR*q0V!`1*s`$k5WLnNxJa?~ceL
dr85@z2pvWc>05HBMtiM`hGiS31C}V_FK}-9$MN$-T8r(+HrJ1X&HWpVXqJfpA(-rP!*k@C&FpUa
?)I}=$9jpEL6TiEOU=v<VGuV>|e|QeXSMdS{57hw0BZ3M8A&nD+OIs0293V^^rxGo$3BC1$4|!(Z
X1V^D7mMY%Fke@>)e7up{C0Nw{hQ<SAK#yh&QAY+5*!7c`|f_{B7OGi?eqU0{cv*p;^e)0)$IY00
Mp<8%@jWDbUN4$mw$8o`s56r|HdSu(+@6oPE!DAGP&4k^207ZJceOJ2wDBOhmX(W`vNwGez=DZX<
zF{`}pYWCYr}@0WB8^&;b4J5xo=i(N7PkL!>*e<06^>3jCNt)f{?{&9EM0spm^LAZE|AX|_0zU}N
aFhov@ta$5KuVQ`U-r$FCupCj#!C*jHcIG*D)8+{>~@Scl)1+?$a{ljww*Eo)5rtfD-aYm1%L&lz
0XU|$dRe_jd9e9l-Jp&-XJ}!t(@+m4iQcez_u~%>q0;y>mB*aGHc`zC!X;O?vA)YPG070TAiU06v
8y^BT;2-Zzc6Ej40AP^!B2PZWBN${3?|?9c)Nb%iaA@~EzKO>lrQ>utqw;p=$(7T~t}YZj^?I=?;
lD+c;EAu-?_vkxg@9TtQzU8+CPBChzu?$^Flk)u1P_AH>dFkK>2=g-*b~4NSU-Mi#0UEuM~Ushxj
j*YAI>wZe6iE;z{`-+eVVs$8ZD>(g4`rm-Xpzk)}+nbX-wr+^X3ImZy=lW`YBKacRElMaA|~?2$i
LW2e{&PsRC*B5%76wco?+oN=<6G;TE4o`9~-oc7rERsBQx)b=@*V=+#^h(FW4_)2G4S5Pw^}cuT<
G`X}^2J^hs%YhZ5#Hn%uKa`%Wv;=UrFw5r}H?DgL{s9go^MGQnVl`;BgH(DN2afN<9-oXMLZp63c
Vc?_OVHx9O95i0S__R?TP4|FCVh^KKuX|8Yaj&<z;$E*@F{!9{tFXY-^4h!w^kHOzw+N_PSaW&MZ
3G~;0Gm|q>tMeY*lwR`!&?UA984c!is;*Dcq?;@m_r59@`y{Lxmp7<Vinp;;#**WpIpJQrk<*2r}
WGQQ=>8H4DEiR$!(O5<Er`E^rume%}#66<T@P{*(e3RfOcVN{O)NIx@7-x0|5BH9#@W`)A(ZNa2^
9=I0Z_-$jw3gQ#=M)^Gv^T&tqm2TmM)_X#sC1SR9z0%P2>t6QtZG2#5F4b(Tg`ScZ7sB$hq82M!p
IB-nVxO}_b9X7->2FzR=-0ETmk2Q8OsYb5cP2ZuGf-?rdt+k&6ADF~AR2^mJ~_pj*KL4B3g=U4f(
Z57~2i--qRg6KCvuidFEzp5!8LIsdB_u3s~cESVr_RTjS{5`7f_ETLmdv?W2exr;LUy*z$l1o5fV
1Z?s=CJ?bNnguBd;r7F`UiA|XbFEllET1l?jI-;ciQdV|0FbRb=$!iG}MAk9JA#24>%EHkYR!tSg
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
vnQ>|@dIGalnCM}#VblG`D&Cc5P8-Q=L+*zJFvy?x{Mc(+Ij@2cwm<M01H_{((aDERI7vN)wNmm8
=U4b>iaxQ|pjRL|so125p!BRa5lhSeL1TKsqH3u-`_s3=TqD%~?qMJ*v3HQ>GwLm(<)N1MXXTgX4
81hiC_Q59jK?%>=ci<4A+84er+;EK6&0*MC;)vuaeJ3!MG$^(MhkOw&j=T60~7yoBur-5lf%-+#t
6^tvF8jB=@pcXU$K`*PY@#?0X$MMIo6f8?t5#BSy&9Nf1{a-d(&KJmGhVy2yoR2Wft4oL8QSuT@F
u^?0FRkU=aUHqjyb}41i0sj_xXDnT^fQ!fLiuRC$Z`-3{@$7ZFLKkj6I5Wj3u-~^Wh6a?C@1V36>
fTpAdD6>x*lrMl?CNr;QM;aTcOPPD0xLYc*cn<MCxxPIi^1lqeIG&fr=XB70`O9!aN5$Uo|O8rEw
1yVBxjE#m>DOok(mJ(9{8{HLB};s;q+*pf}faGn4^XD@Rm*lwE!Z88L(b(~EdSgKBCi<OtQ(?#li
xx{cu+0q*|ov;Q)YR&&k!+uE3>NmJ6aH1G-$&_?vvUvG<Fe?|4vo#eAX!%5bSHr0m7*^rMJ)(r25
0JDrRAfV#i$|3VaolVa;p$IXDc!8A7TNK1R0~E$IG0Dd`c(M0_&;aHHW#m#lD~fDJWvSO&tbH}*f
O%R$sV9wkv?a%mpuG{?MXO+e7qJz%f&S&Tv_fG$7(CYUQYpp6gP>SUr^%%v6{@^)`{7WPUCT>`t{
0QEf>9Tp;1RzXICAc=w*O458Xin&09>b0TYQ<vFyak$aG)Ad^<W3KNImpUEVHjHLZsU;1j&nA?+)
%Zc+ft$GQXJmsz#gupL7h<u;d^nS)L5wZ0#k7C9c>6byt=ksT51PEoa-voN?Q3k>fEEP0!IjIhx8
<YK~rX+%oCY;DN#iI;?E<;qrE**n^G>crD~O)3fvuGRbo2L#`<m_!_Oj1WI3+i6Yf1m#9)zH=@=k
ol5E|jfPU;spI)6I1En(yMyMYXnIXdjOvrZtLXteAp=<|A%XIR4eC%iZk?ZZP-)j`m;5w*WGj3`T
at-g&<bwts_f~bc7WEzcvnc4UsR__V}*Jcr?S@!_I!r*D<ZPDg-=xtF}10fCZQ^eQhe_>$3<F59d
Cke3-Nl=<Zq$`kyJ}ee(=4g#*N6hZ%i|#aI!G`K{9MQUoqZm`BAUzfmFlNdMkkGPaZy)*uQxpU@$
x$91{F&=?YZQJpbrcFTKWiCLHFig2pw<>>G1#ciV~<z^u{n4#T;?EKJNj(m>JsNS>CM0U*&nGcb$
hBP1dfr~k1bGl)=Pbp(ZlQ>vtMbcHDB0O(`R|6hMqT`>n>qasRhd<_P?G#vHWU8+1r;AA!2LXmw(
Cf}k6B%zhuaPZ!p6o=6q*oEmdhao_1WmK)=tXV2WW)?Od)*B924>!{Iu5=7m9lP}h>3>H^W9VP`g
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
_bq9ggeK!onyWCjfB;Y+nbG`y$(F$+6R*(e6pjDb5=}{4bRb$Lj;LX}%BDD}mR33GPA^jG6*I-gW
DePCEwZezQXsRN{&XVdA_TfT;p3-8tDvk4QQC$vzR7|YAn#F*0yN+YUc~vwBAfH)Y)nUT-VWZ0DI
yPA!&15+&U~3tI#`4on)84ZF{XI%<Yd5OQi;zw`3j%1?IOPoLek|jN=>6xwk-N`gk7Xhu9wN=Y5N
lW^b@qBd`MCRLPoWRFN24HoXHlF1;+vAexJtX;YA9PNQPktKIW3SCB8>v)P(XU(}d9*B3Ix=_AHO
11=?q3vzQkU!AFkJ5hip-l*}l@OE5|DaYpeCpdDa7r|b`Xobm`{gb0&gF&V<IhI45L&xoGy>BRL&
RM?rB=q^D=t|n8K^!WhDDbYOnpX<HkFhxxZ?UWA^iTTXeQdj^st6-JB99Ogr+QFHfu_nR8!3uxnG
X|EQrHSp%<J|K-=r$ZB*bieiXJ>C3MM&Qw(Buf?<=<{9<*m63xk$w$r)j4+7fW+Dw>hiq6Updit4
27{8?ES%d33D=IHr+-PfW{<$5()Y&>{uEpncd>m7s_9Z9U;V)XEkuMB}IE7Ku23`#?6^+WLabFZv
hoZ?c@t-6!Y?htqn?Mm91rkThW9zc_ub4=u){j8Cs16xpG#`imzGUGwsTdpPH+78;x~Kd#PR*oRM
`r>75TxDTJ;hDRAkHI+_R!Rd>CBAZ6GQw%bCOoot@_8#fyLYQ<BtuR}Q9?&$I!5)8O5+r1E3BLD+
>6$8-W-TH#+Jb=d4`mn+2%oER3_cAUArf@L2*I;r98eT>hE_mgOVtojerrvVg|upRt$Wf1*O>+S^
2ydvN$a)5z|hqPGMfR=Eq59#wGHkrghOA1RSKEVlx^M&uHy_7E3WJYnI6+}&0z`HGJTFmItlLHYb
2K-WZ~^UzQJcsW6s(eBM=sMVMfURQa;8d$S)nD#(bDDE;WI4@=iebqgy5#=BoowmDyKM;54Nx!{9
xu337?380@tVciX`mq<YC>(t?V`ii9`V@U-`J<~)f`trQ&k!A+FkOp{Cfoh)J0mn_#G7p6*nvn-O
S`AQL6%-5Bv^od%&NKfCqIQf}!ulUC)4({~)<n`#}=kt>{XQyx9oS}uu#SWg6V(=gu4ZxJM|2};;
0(`?VzoB$7iARc~qOzmWd^JW(d1N7}@^w=1r(58$l{1&70A;1f#m@hDfAaj7=dVuM&raWPaTaNUp
Ry^s<esJ+B?7a;?fia`zCQkW^y1{*`42FtJ;yQ&w@9c?>=Eph3f=jstPAmxRHKc7Kou(}POH38k)
yKs8QwsD#5&8ELP?kbWwzwqKHFortzvX>CA-)K%WYy{ze;N_wI=9e0FNwH0x>F>Crr2EgwmwMie;
O#;-<0AfXf+!QZc%a_l&@ZR<5KPP)In5@p{ecsoG-LiV1J^Q4u_i4Kr%Xi1{re%E@AZq$$UzRql^
!tn+M6$)T$g(7Coq4ggq2M?J!nIB-BXnFXfMeUNW*LRO+CgBM1r19+5rPR*Y4#z5XVOcqNA1`xqz
YVq?J6^luD6xf49TQs~tXKcxrC}ZWpbK)S*vkapa5uOqAtPZob))9XJ!(+`~oAA7J436+H&O^_Fh
VQ5(axTuNSr&p!d|eT&<X~6Z4>@>?8c;t0Z$6Mo$9I!ZIYN9De2inZOJR!_^o$Pa4EtZ$9CQu*5u
Hkt1u!3zr8vRma<_r}0NU`Y<{~_`FilJ}MFwC+i~}BGa+wS@a3^RtcTx=)GoAuH`ii?mv4(jZr=E
6^W{T1U&dN4-!slgbfR7s`#g!_R<gnUYrtiC}`9T9wCz7s0?gu&|;a&#RhBJOq<OsNsU+iKZc|2!
}e11k&2XVT&D=ek$^UVZQ)}A;{%?(D9kC=rBnS*PxAZb}P^0ABC17DOa#PF`c=>VsxAe6&`<JAr6
TN{J!&^C4Sk8E4}%cC&kL@`1}n$x86s<ef|g~FZ}g#aTj$qgtw=gjwl<cV}aY^^9!DRQL_+B4<Y4
tf3rT2RVmGDEDxzV-rmqhuZmLbORatG>Ak&hc`AyQc|6W0A{Bl0`<|zKf<GD~E(d2Ys~2&51mR6K
aY?aD2CcP^<9PHVOm7M7L`IzlpL<)l8RnoT#bG(AQ2DO+z%e%JE{UrKd-MW~Hi(qxEbDWqS{^7c?
N9&ETqtk(E~7s9e0UO@GTY`NuN$5KA#C)T)bE^h$upb$zoVdZ=9^4O1c8k>7u*^9YY5_8=xJY%9V
QUm@`hboXX5A&&th{MQ+JZJ|-mg#Hp);Dgs^>a{5c`F4WX*a94g7Ua=1MkYEHPjAvQegEU>3pUD-
ZdMqW6D7K)gsssgz4{rMUI)*qEm5zcuqDQC*y7i@C`_-k*Sb+Ys?3W@WPNq|(+TF(zQvebACcR#h
6A(xPKGU>=c<8UnQg)AGz?SntI}QVq49B=lST6GRZND-xTU%ed-R6=S@Bxc@@KUvn8)A}zp98l5p
@-RO<d`WiGTSDy~Yaxo*^rV#=Yp^9-#u1uGMc~q|?}oo{kskh{mOtax+S71{P9OKwY@=F+yL9k|B
dmk+>)*PUe2UDynu>3|~Z?CN7YNkbHSs<P<)aKXvt|p8n*A?5$?r&HAfsDAb?hmZ}c}Sj~~-mZ$V
OGN`W4gbO!M?ykhlZ#`#O>;cZ5+%UXd$^APQsX|Ajra6*PO+7NzLu_)COuYDZ6+05v_?8c*HT%pt
j5(YUDp1?>F$8@4pW&d>`Zj7^9k*T%e>?oW(L#JwgK&mUaR}K!XOS)EVYfjGAg0k{NlVY>J!*EaS
Euo~2>C>)U^XN;Ri?FbM8%ADvd<}#>!_Z{f6g?`PPD{l!&Ts6<c&w6F~?aeab4;G9-Ab?OYH`rc8
QT2s1<D1E^Si>ok3VjV?*oOZ=I~n#TD)GQ!D7c!}5kCZc*41>#ULf+r-m_C6Qa8X|kKD9?BhT@T;
$!h5|d<1+kvVu_7q%8sES{CIpS6l!GjzTAjYjA2vCUYt8|3s#$A?XVAqpw=E2W$8m4uPJIyaXngF
zr!H#LgR>HpG=s(la>LeBm$Bl}sy5~^?!OkDGtpSW8eYM9iXy(CD;#dqX>bh`C|J5gW}CexgS*)2
5^LCWtx8mN5R=hrLe>A1yF>R0eW~kaiw9E%Hsy_>bZ9D8!*UjO9Skg^US&l8KO)Szi>b%X3^k3Jh
V|vxQq2l-gMZ^Sr;AdUvD}oZP=XY2D7EkKITVd;#=Au8sf+Z@+w;-!PsiuS?@9H{r!A|J^mU_ANX
VmrZ}bDa(gy}JE%=Ug8l%N2+W1E)$@FbjtK)!=Q)62ox_6Lw7<Ju|PSpK1-H7wu>e>0rGlDJNt>@
U@c~VTt_EL~VIpyoCbLKMd?%!cXA-;`=<C<#qgLWH+MkgA802?2@KK}mnIi<I`*m?f;4fzqmM`U{
C<2#V<Siz3vU!0!3dv*K^SsI}!&i#J3OFEuzkAsPE@CMAJtQhMb&tJB>2hUEJt*4<#W9O&muTD%;
-GgtttT3voE_Hr5Ieu}1i{`hmOSKGP0baIya2ZpkMvt1j`SDc?BP)@&%|!PgQJ*5V@Ai)Hi7`Clt
nBz`H|UD<2PKsx?N@X+fLDEf-5X+<6ihICao_3iFWViDN*x6~XIo(tSbx}N<DQTib4)ZKA@vMb-e
#8CQmF`*jS2*GSa$e6SBsz>OA#mYo9vE|iZRCoM@IqLY%W#a0glTdS4bI`b>f2xT7j8_=^cBIS_`
d&8Rm@Np80HXRU~q3anRo%Y9)n6^tH(jvV{rC5riddZ~7SLIfNq?V9yOyR_M&{h?CxgX<=Z-3PEY
Oe#UsLH!O=pRJUJyPf+mYD$P%;1(CU7#4yaN;jT+~BIW{AL&DK3RrDAS8=)jz?O0@et>qn)S(G?w
U=wJ^BKM|D@tC}l9vGf~RJq%gpv$PKI^*lEzK9goU6(n5BoByXezcqiE!nk968T=8P7Em$>991?q
t;7v*_-H=Oa)lfs1B-MnZH4KW;0lf26D=tl$*mO*bx%2(n!SE68|si8Fg?QgeL7-Q>ot(ukngXiU
U)QSrEKo$jiq1kT*uADf7GBTSb(Z^7gIfPaT&$>B+C8!$o+i5bj*8T(`T2^VPh>B$|K@WToY?fY#
e5fkm!ra`@B;?dzaYUk&|UcxNzvMhnO72?g(dKpr(OUq0Xa_HhqReZC4~BlA*BKSEEaNp-HS#x1P
Wf?Bi@(4dJ75GASOB+ARd=I9Q*LWtp20I{?!M;4mJ^BIPRmxHe*r7vmmv0;^oMd;Mpwzf{nU~Q?&
1{+&1h$86j$!k#L4^eSSz#{7`cF_dP5_NBSG(L~6;t@|Sq?UZ{=WifQz+vCQf{GduVVMCdscuV|U
OT5e2HPNAO}@Mg7heyaJndiXJj5&0fBwfe#M-prclT=ewbCRoU|{=Lemq_?$Qk9k40K{X@x9_|;F
0l?QNV%sgZ?36lvhXxo4{TtBf!;=;x>rAT={fcEYq)*i4z+OO{~L!y`;_gr_;o+?-RUsq7tyy(K>
m?7!Q5ItiC>_P`u#hE&IfQK8Pg~<mFS)Y)sZ@pNT&=3yb=SmaH4`aGWpIkp_HwJdT!mTyk+#W~4k
LIMhgDCVSVKOi>DY$j5feXB_nF9cwoJNoCys;<lD>-a!v3gape{)OP~H(sf+;B!AOEin+)d`qV3l
?W!0zPL6n0Evy@sbFMfF2Rsj@;R<hr3W?q8%EVtlyQ=mqyNz811EDxc?oAge+^f>UcqvWu_F|@bv
;F%@uFFop*p*CXJGNXyNNrxKZ1JN&P)Ej$CtSmhvJFI(sy#VR#vC&*TA^t;qC6^^kvA-Jq_|mfj?
02UddT<@{wa&TcJPY0QpOO+>^{3fORFeV^A(HDD@`7nyb~jBpe+`Gu5r1#`mWe#wftcD&Tmk8>2t
Be6WZ~VmuQw)@^o9%f>f|lMw3zN=n7_>hhpwrrlQK85*1OiXtC1fX*v+2G1qkNv2<{3`c&y7&9|u
Zx;oIuPz7E=duD9Q%yvMLR47r=e1N_uLvD>6BdG5Nrk-mCQZBk*Th0rqz&?Q{T_?XCdg<CMgCnx6
q#&8(#c97%K@BC*nu4@b#*P<C_hK?KyNu=E(<imyI=7=rc)RU!APosJdLL4A%iBi%N-b~gWul-b!
-jFp?0Cb~;U1-ZqsiRX0ecg#x1C3JV@)&FP^z1f_RgnC4XT{>D_gV^l6}SMMGA%03|1h)g2)@k<N
$-|Ix#U;M;r8$_N2%-DP53afUs`+pzWX+Z4Mj|f0DkeOna9=>BND7gR*iaMcVkKXbzUko<y_C?o!
VAjtmBRgIFq5N?(V3)q)eu7~*^eWJ3{DVQ0t?UYsn1L3;J~pM&vDMA}Ym?W0|UTRJK?DT0yCk{6P
d|6K)rx5gxT36gG-f-R~|1<@8@ik@^V4k$DLXw=R|T0zP^J^-V!V-_<sT(lfRywvW-kAw<Z&Lq@;
d(u)79Zq?RjC|!_6J^C0F2F$9S#t1IWBsMxB97F(yMm(+W1j;_;v!-=jv4B@GL804d_PI9;gHt)3
8_t!<$6^IPJR4W4oO1zRi)>|gpE42BiTojPW_kQ{QLJ0T{LY5AC{AA%Ew9=Eh?tch4r7)bjloTP3
JycvY_()7Z{aj+;ME0Ds5u1C<CS?{m~(u<gvArUAVj_M-Jg$`m)`~eFH>^Wv<WjrV>M7pgHYySTT
U&#I>iR-Afkta$(jt31$%_%8MPy;ZUVDnc~;q>@$&O@q5|cUg4xFQMC-(e~UIpjT2Yp{wdo^e+B!
Zu!%(<=S@6jfftOI%8hXmJCqQRCZ1lkt9JET;_65Zs!ll<X4Q7VG?IuCymQQbR&^~sp^;SyU=^Yj
b~%hA)@qvF<`4o|P_lmeO(nmfr({{9;(V%S-Qn+i<|!|4ZeX|#@%c)8344m7TcLgA_^wR`{o?0yl
MtF4d(Xayf-ty-#^LZg*Q=0R2`#aKeF)t&g*>Ap3PT!(Jlnlt)nsXP1wzPt^yFUM2%~PB)v;Cn`~
>jGv)hB!9c!(-j_e{~#F+>pqe15~0o5F1?b79kGX=T@+1nExURB!WAC$I7*J%dbh5(4OXP06K+?l
xGTxG57TCMKoR{TTR9ekypHgt(c)3VcQ2B&yKPoEpLeb$WJMEIc&DsrXc<)WJ!PjJ6_uWQEE3Zt&
LF5}Gl`B=MG!de}1Aur?VvA*86j#=~>NE92FW~>xrLfTT-_w+1I_#!?1<K)k!WlBl9c_Z1b$9NQ1
Z7g;&R;~HI#&Us#ZYc$@wR9^V;W6@&I8kwdrg<V4z((qy!9gn5;xEEPmJh-8px$(7Y{7!A?|>qM6
kY;d+k2;eVgLOMsee*xzBEelR!keG@m(NBb#UD<5J2*Doe#!Mw91Q!PMgqH^5D-dhrQ7%RqtBGa^
K*NZ1W!7E@>m_H3jLBaehJb@>VNIX6Sh;hCGX;a3TO=&^@tfVMA(mq=X$6XXvSg2Bud?X_cS}%ej
bPyI|;ouYz}PzQ=mm^7@86OYyckSf)l?1Frv=udpNPkgUnxfB$TkGm4#`zI@qs;~dV@Yhmm$#l4r
u-sPzeTbDr9ptWNhh+G3C(;~+B)QjvcAgiS!nYk)3J{FL5p`5Tf$uS^5WoV=xgKvU;+gIhzsGZ!Q
NQ=s<&o(Z`j&_e|9s_LQ8|kAT;<sHmcl9G}_DR;VH_P;6SVY%sL|mZ*59M%2stBk0(^EXvN$-T^F
}xbohTq0e-~P87R8`0IYmXP>y<TW4yIEFEP#WZ>#eV7H;{Nbkfd9qC0u9VB?z<5gn!Ek(%B-Nm=?
^bR=JE$|`V9Z!8)wa%!C^BvXa*hr@s;X!!!M4{%}f;8=IB;<m^XuO*VR6G^Fl;H+|IS}?`nljkuW
*vod`iLZWq_lwz&PHy@~dEgz2=Go_+rwetW^O9sDLY1{=Y#vxa#$==A&hL&mK^4?kmR{iSIYQZCF
Ah1y-QC$L&S`~W}ji<XU7sHc}o{dmiXxg|UIy~95XVj0%1<lSM^FM&L{y4n`z&lG{0CPgugTd<!o
qaYF~KteRQ&ne8o7>1Eza1|syOm^r}w9fq8j6du>0!-d-1_K%fs%aggfK#N^f5TT!oyS~<$Lv;;I
<MmN+N%V+W)CVI(*D68Q}HWIZJ)o37iSdE+Nt&}SL=FX<7&?ZCo$y^g>JR09`v|sud?d9o2(!eM>
6gs;Ov@@_jrPx%9>{g+qYz*#eR6xn3dEq9H~w-k9h$5)y;75ZkY8uluw<ChwA|RKD#4W;V_(9-*P
Rwuf;89Rg_Ub1I&C*xvuSshx_Yb{B9bh(c*cQQt|={YS3pYWs&l5Z|`s&v?&;t%(xFHa+K%UI3c@
BI(eOo6T(G~0*E@Ly*}>Y{eH0jyJDCoDup}d;_mj~*ixal6OQI7XC?YpU%{%3BD^j>#E8&R*L`1g
{<1Qx;spuHco^b6LX&ek<<&My64sDNxLAU_B<lx^DRo6Hk!;1zD)54iKx&$AS~znQbi&;=N^&>FF
btj?m0YBpz(toxo|GNx4kj_*2a(G}N?a>Ro0hy;&|qy??^2WMN$K8ML4B9UWC_6p^W9PhKm0&lSW
w6I1r)g6GBlBHN#Db3zGhTPZo}(KqL<q6(*($8u#@KFV~YAFx(zT9k9fTjlK95@HlU0;c3>QGh~b
EqVF`~KZmKAS(yn0v@<XUUdh91!q$zU%&~I>G>;{LPG6cslh>AXeV}Dq)mKuVM5_@%e`i;V#-O9R
$C6=a)^G#>JHuRavV5(`jQ)-wi=>>%+7Hjb(Sfwu|^RQix6IeJ}T;DpuUN%M;Hp6ve4XYrAcF@9h
@HY{V#4$z%gChk#22&5}!gO5hu!RKavPo3Z*K-!$t7bOEFIJKBQ1)G1qc7=y*im{n<VKgkxEW0~n
)YqWDv6q>&3@62X^ESWqf~7e7uuw(9hC0dHmRx(5w<bDG4}<lR&awOp3ruEZW}&%eQaSXR+$b`Mn
TCowhpwfI##qEJ6`DkCk6PoI6|q1BAaa!Oxg*3=0rRbWg+VZ5-$SUrXf>kG&(O<^Y|#Cm<j5pUIU
~eVA`g3RV1~|&@KmA+tfBjZ`cCNYVaJKjf|l_3p6T<jXl<65s!<E0&FZQ!n17-J&mMHOX6sNAVH-
Krc<yqdBhqjE54Q=SXMl2t&k@Y1`R|PtAL%am%tI*5j{Ni#V%19h{Fj1!ZB>=8(GggF?nnoAQip#
RhCiCFR}@8W5@O#%M!a6H71|S(m{R2;MWUNW1!)LO;N3t1KLQ5nr=#lFY3h`2`eOV<<2c%39Yy<g
+AqYM73?AX~x5HVAI<2ZlG3W{-HcJBu*<CwU^rv)zp4@wVa~r;Y+eiQJ#zpvj+gQ9TgQ>z}R53X2
o`^r<AxsaqqcN*r-L9W0*XH*DVLGI*3ybfWxPrmFH-UgKVQwGd-2zF27Ns;3?D`AvS)p!mtr=@q5
Xl7A-w5c3k2}<ZNAOhulF4yzjtBDO`ZOV@KIX%3{!17g5@-s)tzH0Nom4BWX6GA=I^`hF@+;Day%
M*^c27B~vd+H1sx-eXjihG4vAJd?8C6>)Ql+s-vh|FMw5n%}aRgJeNqKM+|5L^5usS2m3kVXh!tb
%3R&C{m<9onNb0G@efKQquSfX!BIs6{74B+9wdgOq{MAiuE%8uim%9#maYfI?gltmylReInnU@bB
5hB`QHa?H&Tg#2GDEQxz)NtJf!iJ#<kDS$G8=0&{gzZu#A@b}rEiQ8yTm$?+~J_v?~F+ZAN#plt#
;K4h`*FPK=a|%(KMP}P9k>jz>uJcF>K;QV*5i$EY@w*#8+4!kfPp^O4hylzKS;|@MzmR!>BFIQEC
xJju*kxBkOg4W9}Li!bz^YBvu-3wkjKW*(19;sp00~s^*Yk3Qd%eN*H;5{<g`PdkxQ2qa2}vZZ;p
dK?SrAAG`ZCwjKEA8lPFhylsG1nyY)E$?*ls7G+f_<0Q^E?iV8Hz6mCWZ;JrrFrx|kK7<i%9KSie
Ep>`td*?QS*)lIw07{+K3j+jtZfVv%Fmg>eHL(PCZivesTGs1ok3qX-g_V^_C$>Y*`gQh>62eof^
U_MN!PH|#vYrE^vf1-&nk~*zQ0UucRGcJ>?H|TBS(amorr)9tEpUSunE?A~k<6#jO2RA$1(`L7E7
D5xqeU}mz3n%L0g0&}WFrfNUrVCAo55V-p&g(hMT8Dhvw4(Ur&gu`w@o7SasdCv1}kiq=2^9rEZB
bc$97ykKa>+Q^1PB$jC6c#pn`V7WbKhhE59*yLM|dI2@Gr+Trcs?0v^78hXTggJ0aq}JLOG82>~e
D@odga=VNV|LvvLe=NxyvveYqe+^lBWO;MckgqcKUW4%jw)kdeCOFp_Bozc#_Cu!mPWD_Gjig1}s
th9S&FtPX#pnz3i_cY~4jtmov0Dy$Z_dCh?{PwsjHo>{eF!%*J2A$m`3)tz1O)1fG7`mky$vkT#%
cr&EPZ^kFw_$xQ=b41(wylNX`>M_^?(9pph53<mmT-LrkrRim-Jr{VFY=&%OT@<Rx+G{3BXneYx)
^058-}Wmt4eU*cy_&1<|~y2#ci-J7*$(jq?C?*2hA%h7={UpTkKO+VdkjVhhkD!h|+REk?NzpvWg
jRrS}&DrCkFRZE&p#8$TFUm)3^ZB|2DHUcxSqIn0e+PuuEN_oMBdbsaf#*@d9Vrrb5~V8TZZO#HF
3nA^N%vQ=3c<tZ#&qjJ93A#LcI_p@TU_PsW^tSs|;1v^=`iL(MG=Cy1>wY=<J^Hh1rT2eF-2l5ZJ
b-?9&+xNyuk<VmBjaM!0k)*tln(T&D;eBNP(|KTztU(ZH>&nknzzb9$wI4pnwW%2UDx#DLEz$93B
bxE-syhpHA7~0`GFT~}*@`UpD<{jnmr8w2vzRTnZY^{xrpK+K7wB}m6*)S~^m!l%&bF1Do#H{x%P
$bzP@NXZt?ne0udZ&?7iDCwNs=tCCP$@xEek7FqA2YwQ@WO|#9(s!<CbjG;F>LCsdTD$UA;iZy)^
0s#yYi>Bfz5zw9(yc<q^Fmn48F^R;zWDEbneqTTsvwtD5IcZfVcV=4FTBHSUudgO~&h3Q;x{z(9K
s*SEpiuzIn{(i(XDuC}YMrVZt=9F<n}DqLfY*3%+Nh9H$&Feasvpj?4Z`#=Dc@D3XfG3yao#CXrx
IH)?~pfT?={lK?>RX=FcW_6TYeesSo3OQa4zt!Df&zX5}*2O`zX6@ZKLdma54>#7tX_so^!%Z~>8
2u{v)YVbI>Q@1<wia7c^DtlheEx_<O4EXRue@*em3#?>yR|pE77uEgViS_;!TesE;970*DhWeVUj
AAgDO#%-9|Vs&9h%1446G{bCdWj4;I!f0Y1T!QQORsnddMT!<zHRQ5jQKJU3YO-)RS|he>W+_yIQ
qBbefTCn!XyBaqwOfGli*_n@Ou8*|y?{)~DMpX&kY&HfCoFbq`G`#YuhB;;5^kT)LjK@(wcts+D|
Ne;V5BrNfeV^#dK<$J4qxp<(<wDwS%^%s54Z<x_~0g3$xY?Il6yFj}nadoKqLCA;B-UDQI;a7CH`
<_&Y1C0fFMRi;<y#mcmz^ob#9Sd$5giu93&&Uc7XMw*{SmoZta9t8uD+}&6U>H^G<nxKWUh6!J-8
nZ?^n>*2HO}n~d-SEI_bjZ;dP|MY*nfB{<f(D_bSZom7&-5$S8HyIMQJLa)HfQ~Z8W5(Qn9VKlD^
9N#{t0Kkpf&AlvZ1Oq>Mm!L3w5e{81%cHVeKs&-vyU+H-_ExXrCTH@HFUl)-+3@;8MvJjEAY(Nv4
Gs#-(?!S4Aepiuy`a@(=0D&?9#s{jDzF4R7w)WODMR{9|sVVPHujrt~h$xr*HYoN};8uGz(v;#{?
r4-Ll#yq;#4(KHVmg3F^3y}=Z4W{ydYrejfxx9j*8Gp&przZ!Zx5aY37P#q!4@we)*e<T5pj?%qt
(;8!*t{9VGaeiY?a6J8V&uNX>vLC}@7>B?lOPc|w;o|sh)8ul70YpB2od-~J(jFs~COzsUdGab-6
)eMfKoRa7-uM`=S}?>Qnds&^)JR)irwJ#xlO<8kla`kVCLKNu{yTXVkVhp3R8rTrY0&Mlvo@>O*>
wW8Zyv{iH6NI415Hm7a)*yDQoyX@=4v?&IQig}*egwzWHx1H{O~?blL+UE=i&8o3bTaa(QN~?jnS
t7^Ww#AG^J-iEQ?5-wa_DkhJ8mN@(3=^5;O%OtEdQ$poL^7$%_S&qJ(2CBXlu5Z&G+38+V+kb(ZD
OZ=PJk@&o-&3v}V&+ivzro5^(>MjAj^Q6FX$I#c7z_s6eKMrWsg$B4;$y~hWK7wPNMH>20b=g%?6
VDBP*^W*E$^B;~W4`T1p0Y7;6{`B?n`(H+{PTqWf{sX>x%rDMPp1*zb!hO}-|Mnt<ujj|lUO{KaF
Hg>YfyW2?7wHc_zI+Lt{rv3o97}eg`FHP6&flM$;M22TUO#*Likj${7u1YYIKY&Mr*BHnyFKa=22
gr@{Oa`kHzzNg=Z|S+Fy;OEFYiu9r*D3OQZLvd!aV-z<o&bb^V8P>F_z}Jw8-ExkAHmg{OxNP^w}
A`qy75s?b+%1>DxD>vsZ7a=WwsXenWfcI&lF1qsIn(e+17D;QP0Sn1liz^u9&2<&&S!-ye@;*rDx
<)TN&u{p``tKK(qRp9A`NOh4o`;~!_=Hu0z1k^j5$e^373lmGYS|3~uwf#fJr7RjT_Wip+N=2@QL
J{ln(qqEN`Yj*Vi{st#xnXwx$#4gX(q4@DFUS{A~;$}U<7v)?oWI$r<X;?vIitioNl&AL(9|k?Qq
YCAcs?mMyxf~1<a+0Ty*xV4^X}iIbCtSsgJqhertS$N-{CIYJhFh{4oLqK1#e9OVK5>|U@PwSPp^
z~H&vUyZdPX^3VXx1gwItCy+iBt@)>^s~QA%yJV@y)MTr;FZ`FM^-NtzU+QHWOGZonA6d!AmklXO
mk5We(Y!BpLqqo*(;0L9f+yr_PekH}}xGGW4@;AKB~|Ik=G*9YAj2V6Jf@)cZ{WLBl#4phCNZ}=h
2l{HH$){t!tMDapnm`{vuAe1~3O>5;K<Qwq2Ecg^JG8J)(4H#iT+ST)D`SU>Im|iL71!l(7NJAV5
o_@R{B7HY1*2JBbVoGdiQ;-05r0~Ig*-<bwOJYYG=&pUOeMV>>9X5i0LWAoNB=jHsGaz3KtRC*s?
mmEDF7h-Qu1jz&lI`+2WhNe{Iq;~0?<p3v=g!gny*8e3xqbx>Szv6~z0BkIV_hG}SCbQGg_goBmG
{I4($l8`9B$rSS_;@%(|g4ZH6y~XEj{K~OUv>^z_2CYTSr{nN4mA+lEqPTQtxgR#t~Tkx3Um4Y5$
!-@3w^cH!!JuHIvcY)Q!YudF(D%c*lOz=A*+5?WWBG7`mGtN<YQoDSRrK;7#uFXfoKY+VCvC2r<!
QwaO$3+Iaf3?$VHYs8)zo5*Y-|42}^v0pW;&cX-k)mesc{c>3V*p`Q}Q{1v;FTewce&}j1mY+&kL
q7z9`JpqIsWmsT<H~u9vao02%Rt|-RTeFfiR*W`!-n3yF1E@PJ<0w3Jur#`>J`HVx;80-0Jp91(?
$@64H2k_vIOPPp#P)?$64)Y7BJj7L%PfY>L<zar<?fJ)^sDiUBQD^-V;ZTbh`T#y^8zoQb^JRuPv
XEzAY;A<jloBpRAnSaXuwnv29u1}=H^V;z$tmNvyjUPP(TEoQbuCO$DZyHWhQ1?);pPrnU;CSeW;
gH+d@jg)BxCGvVF#j-m5%=2Kv^q4a+aDt+H^8IBIt?nS+w)a^~>(JOwltst9C_n?e_+xi_lqCV8@
i|CAYrJL-R~MdUP&u22BTDiYZW_oHT8ISefG)Ph1CIdNhvR$bqY%(PX9jat(Tq$)Uaa=u;F+<DT}
%1o(VJfZTgT$K?kQ9B<eo{;CBVy_&u)3jRgXCi0aic(B617J5tqzK+#W>dAH=}_>H4O3?DOXf2C*
LIV{?>}J%t^&{fR~ClT2IxN8h}jygn}MU;_&)^E6|NrrS!6XkhM;^<jm{X;!o_F=R;zqWlx7R9%M
rcyfZjY%<t?$&ayf08+ODOnLdZ4!MiTW-;V2@=8oPrlsDKH+ww=~?Q?q>W?On8?C=O)%;)=#tldZ
2}L!{oyLeR%<zaD(J=>^fk?jt}SL@N^4x@+K9L-;-y!`3gs7DRaM`B6`XrQZ@MF7YPtbafezh=D2
bDOJ3U@6|~>HgP$PvNI3Hd7Hx7*5TaD?3}=S#h`ETCd2ADl^*+i8BGGsLKFYt^UcnH)d8cp&=<sN
E&6M<O-)gBkC4VRC1S#e>8CF=!}I~6o*da#@N2KTNpG?QX>KleBwRV*IJJ!m`4y&u+BZK`H@%mhB
@7K6GuB`#3p)Wp{6=cp2RuqEbZ2y-vi4=gbBS(JexX@U2k5@wqLo1lt@l~<0%xPrL%z!yEjXc{hr
A41@=*XuNId*2bc0kvkE{AMdiUcJ`4<2st!0718}XKk7pqfQATJ`qis~W5`8Q(tAy&Be0RtNgTY#
BF6!&~>98d-fXn3TAvaoz*(hN$sB|cst%)EBYRnIP};6c1P1c9b>ztX5&^-)D*<=Y@)jQpD!zrkp
lT&Dy<)fkMUbZ_Hms4%m{Na;W6RvxzgeKWZAcKp4f`B<W{X_F(hQSuZzil_iFc?I#p1_$?e3fz{6
_&v^B4fj9s@;4dJ;^HQoSTmrT!;u;rjsDZWZS<%QQ!{7<pPXLt&cs*s+|tSVcnh@{wkoSao?lIMP
YD#g@Y8$W8)mWBX;i641^emzA!utNt0Lf6A8@K(^+8v8P)U{2DyvS_4kGmiy4aFq8(W`5nCY7Z5`
T}lBKbXqUs&XYuQ9&IiwOXcH_}g~DLaZsHP5n5+b0Sv@VMfXUR6QSgg#p%qOR(grhC<--j^Du{oq
S<GslBF+-`7>aB#iOzk77wZa2Da4d_1g{?N)f%IZoQ(QEumAaUE+%EW&C*eZs$p-V$OM6X6nh!7A
7&Ze0<;&)0~IrJ&~Sp{@tlaankEJLv_$=0ID{(syHI+?PG5Bq0Mh*-95e*EV*&%{}aw09J(hYU5u
#zTc#T9|~e<O&FbK!(5#2cSp6k$l;J1>=T9m?(n@fHB!<ig5}?=fR-~`w*p;V;`3I!RD-Utpxyr{
yIyu?_pqH(}l6H(Pun@JdQtBct4Vn6fuB2esa*fkH!VX?q@?4w953=mL;aQ99`Vy6>XMs*IwCb1+
^8oT%xvFxKKhMDaq*L<-%iQT*FDb$?GuYkcu2h(f*vb=ptbX)ZV)35jt8Zm*w{vc)y%m#L4wNQXG
0%0wNEMa&uWmKD#!PjipLj-}n&kS{%5T`tB^u#U>Bqi5XILPzax^?^oa8ln83M*avse&dttW>My3
MT0f}qH~Fw-*=o@sOh}(`fR|7oYAU(%jjv24GEUN&G-;Nh?9OX#sK2OmUiQP5v&)`X4Oh7l*}c}b
;*XW^ZB%5FOx3bv%U!$CR!K0ex|p=uds?}mYThLwaLxK(mBl_=?sH7G5Qbq{i2Q3=ky~0>Mj3V8R
)b(=0n|gcy~e);iw`%CN7H6T<HH&(UL%K>8uQU*&5~f;w32mQGbkJ4ty_mpOD)ZA(7)oL_tEfChn
w`Zz6eWV%E#gMYg<JzRa@1f%U0LcD9$LUx?1m6ZHGd_n-XU@2>PRgKT?yzgWLKAUm4O^yObIhTIS
jg7?psSQTo4)P*50Ti+O|2{mJ2Q-4U}^A!HJ8Yy~{oISlwpeafb#u*J@@vbd%;$vj)r$xXEI^I)K
R#+_mr_H7ApswRdu-HnLqcT&YtR92|8MJyR@Xf`Sjt4;-9NbB|*8+TTRqB0k4PUghf0hU*T4rMn0
gdwBNE%tV|x}E+0;per}t8VA8-|cPFP>oEvcK1qxLBL5XJfU+X1H#D&^<77mhf^gZq3b-g_>Q`Jc
hkNpTVcjz_?Om^u2jPc`Uj{}V-xH1We!dI^sXPR;m=I@r)&2nd85Q^-nu~pqA2ZpqU<#I#2hLc=m
WEx1E2MztV~vmTM!xhMrFMpxeM3U#<KPI_Lb0t2KDUMRVl_dhNW{__-jz%&9MRcc56pf_4^xHo6^
}t=g}WwY-AvE-;8;t&?gClz2a>|k_XiC`kc%@jCR*!sWtA#mQaTlwO36YBTVQu%?f{so<6m2fU1B
=l{O!cJR*H}CkIM>9cBZh@$NRK@1ol*UGa6)qwc?ObiJ)c*IP5X-j^QT+Jnt?A<>J7w$cZDX<+<(
2KZ`2W^yz$4ISSRt_7lYug<u-&isXjg(ERagg+-kxeW(<{jFls@SHF(Na%@9+)yjnYtZdz<8vnHG
`wz;i?H-rjT1`p=(Z3L)(nNG_*s1$c5JKN=3l>ewkeL=X7*Y8WVVjjsdK<NPF=eB)K-;#uBb;XA#
croO`=RiZ^#<PQTv-<fWM;+N-AF=V~=}_15`ltwA9Py!?UUZ{`N->P==DUb{VfSPOuwCvyF%52R&
`6-ueuf$z(o!)*5d;1JRXlnnAu82S<)NzE!8^a>o25NVXw*$e?}LT#ota4;%RC3SJfwb*LvWfY}V
Ut4|odnRT_nw0-FhTQIr?_!}q>!zS4hHh%^#p8=EY;gM{B#TI-5gNa7ha<<$56M$Q1^=rvh+fm;t
>CLUVQQ}{tM))FXGrnux_VB5i(0bY3Q)sKg>-4A!8E9m?fv?TpaLZxAu2TiGTKxZG${$;o^Q0E_i
6J-&TI*qjcf45eX{C<lbM#hnM4_u#Br%t3&!#$k5Z11U3s^#dR_XE$n9;TOeWl^DO@um2ZNr9u;_
T-Yz^_r<R+FF2y4srN{u*>2t!>ZpRIRF84o^QX-&T4hC_#>fU-d9uCASuwylY|iYF1sEQ`ij-hLc
yt+cCHDgZ@=+k>{&<ABMjR)rQrv`D4rliLGJ`o{A#Xdvd&7uvLI_*;^tc=B~S9sucnL=scRhd}U;
Hu8z>4%yv?9_^b<hkFjtG&i5yWYj&v2as64eUK<x(=6DcSD8T8rnnQm==@A>YHoO_+BwgB>XDTMr
l2JZ6(w#lga9`^WgZ@&gN=r=^jrrx-Q$$44GpHxKLH*KsNT{Ynr{T0+WHRsl&z&Nz<9>|?lU|@lb
p{F&7QosXTN$i5m8*7=TLllU83(xIc{ZVxpN4c<48)kGuZ(JT15z!U-Uj`2SgJOXNv0K+uF9IH^w
t<2wdh?%UEB1co_bkisJs)Z&X%L24Z_-bj|00|+wowlR((%}8e6Oi%}be+pptYb6q!n?xl{I^cCE
KKz>P5~V@szz)G?{d9F98o-46V7vv9N7oo||$_k+;0Ya~ySMlg?(MULSO#hKW)w39n=X~7z~Ki4#
qLVAKlR&dbl<t!u$PWO;a>XbstQE`>8l}!bqxEKwFl!DlqE!~JR2OUzpw<h<|uw!0UCO_8mcKh~h
^mdQbFxrkys8idGth0XQLUt2!oK*bvJG7P$ZM!WU!C!;WRT(%2L8TS2yo2yUg5AF7m;iyoj@_9gc
QSYdX~&tV2GFi|lWiPn8JpT>l2Vf2axAz-ay{bErB+0^_sO-%OzNg0gkv#dd(&u|1<y}{{9`<gi;
PoXy?hr$ix~%jd%sLE*<PLi+CQ7dl&~lK_18=J*lMBG>GgsV=CxY$RdJJ1{5?G!c#1IwfBm)5=8$
q26bA$JnOJd>U^&;Lk$kiHO){6@YTa*JmzYKfdQRq@?ytXIr0_u)H7v0ASQQ}5`t?^f$#2c$1;$y
V`2_DWOfEyFubebjLh{TmQcC@W*{Prf4K!?pGmgz7<fd1F<kxL+;JZ_p<98Tza27AFCF4y(p{uWB
$|t`<SBV0{ECm8^8a3rbOX)GjRmB|=r7MbtigB7gas)Wen}U(<+5~QV8nmx2@98bV>T5QLZhx5N6
gre6ebTzAjExj6kpd@1!9SKD=VK(j;B~?|XXe1|qLndbZ^0;mcQ;XiDO^nQ7G4V2ep#GL9@ATlp2
`W%a<qA#tT>P>#|5Og|Fo*n$2jF?DVdLo`ucSaYX_B799ImiAQ{yV?c-De;1O{L<_2%js8CYK=A#
Mzm`B&@q|w-TS&xIQ7WZd%M5~2ph@xGNnP0~@NqnU@0)yPPiXOCDz+qhMz%RlkDKNwrxPs8wbv&W
3Y1V>eQXgS;_#>Xum=1Sn$L~vK6uyvx?W!*zY~JWE7|=jI=BwPQayegJqy%3qk73*MKwkYsSzI}5
^|``23Y)kD;4C=oBJH+iib0G(xajalDufw)F`I0s-P!Bx9|kkBgU9?FUtyHZDCo8i_X5n=dA%e<d
RqMh)dVc`lmiCiH_8hE3xaMh9ay>_j$geU{rKke{A~2@<o)P1I=SH`S_gUy9tL}D=#fYMH}b~0B+
>xnKU*+@HgO{=T11;3A=?gq#6XiOZ!IPSB7=C`Y0&G7lb3JbzaBk%`{sn=?x|Cq$Vo7dr?*MYX$1
I5K2OrP^q^}$Nn_LjnC~}~X}amQJPpRv=r$QooyMlYat@RU@W_1%qmN4uac`B{T~xNasBCvp)$XF
Y-6@jC>l=3j<7j&250p|A`(rBAU6krBOkL|_r`*Bn48|P7<cgiQ@#8>!Xj5)k%3X|6rgwvGe~2eL
KOnzmDan$N%FwCPX#QqJ#&*&UQ?k6|TBmEFZEk;~D6f4kbsbMC!k<Hp%X=(?;u2Q*!2PJNDzg!`C
~>%HI)=X%eJ?%ah<21r*$za;xs?bgRL%`4btlo42|_Z_CP9bh#vgHB{7F)gQ#NZFoUcM;xDBw`L9
ag?I$cxz0Z%aC=M+TKQK|B{j{-@Y&48-xOQ1L`yWTn-bk}#lps(qGUVc^wB_Y%=rX2mL3xm{f++l
`9Jg9U;M~QqqfE5|4aL%fXsYzjJNBKBTP3TP^_w8(+x9?_r*^MbIvc(F0unIWKbIjqzR-q<|t!yp
|l|RCxLb8W&Zcoy0=ag>V6?2ZMf+TaxE<eO$iZB>yz6}*7%+G+7zrYik##$xcP_9wT<-R#xrhrjx
TRK5-*2qP-r^zMIwIt5lC^5)9rb+toh?7U5AD7OMEV1AFc8C~!(&ouf`d*#0jy~u}`l^TwBAQH`T
;f=PORxfh?2zrIU3XunXil5IzbXGM;<L3r#0**OwCPqN<-Fl`!Ho?gEGc={ebMIilH9+@6Uy-02-
48%&XTDK7Ao;Vxri(ul`_ajtj8$AToR}zmTuJ2RDg369NX$v2JrO#>*Mnu-=CB=y9~vu<qVOtKQW
Wh`qTeRR&q6G&FeA;Y7#uT+w6q)mz++VVKPZwW|?#cCY?lCi$L3}KDSqGK8NiR*dhfZ1%%rQ4oYa
3ncDh&?B=EYoWv1!G7U;1LHnPJX+^{`^*5<WHekli0pIn>IB+7K@B$pUi4G*&6s6t!%}P~*sUEzd
e)2SdFpFedgqAv&<_P?ytZn68OX20}R~VXr^I$%W#xeBp5a$I&^LXwh1@KlHTP;Vk0x;^7Ry?^T^
{?7ue0YEkte7ysEDg(6H_>ezDACuJom5Hz?4ZFJ7uKzcPI@euMD+|wVIhaov)KrHi6TNQ8PxT;p$
Lx3Ch!L27XSeQ8pA(guwF!HY7)fSY;*&|8e!mg&fdXkY*BHLi!h9t22^WS>Rgn>qx+b=kXPEzHsS
_^*Mw!iTVw^PJZA0ExsI7YcqAd7vN*XT-ZLia+%E_tnCM-!m{`x$P5{mU>A}Dzsue`m2akVN$??J
<m0g7??8ujPQ{y~{TB`l}<m?CFz-)}-Ndpyp0EhSkH&+MX&Nk^YnU&@3K`08VTjV++2QCuN7@sF&
bgWegIdIH8IZ3Yx1P{NPOlE?IT*x3Ib~fUNA^+ht>6X@!NC3SmGdd;-p(O24gLvu~>na3cXu{UUB
YOn$Z5Ywf4G8e!<m}|t$@6oE09C9^X(U3+^eRc?xP!cFADel&P2#%|Wp>tV0}kaDHy?K~=nQKoKu
ct`Z18HUJ~TE0*EK13$j{r7CXxgj`#H_B^ir=cmNDz=Py?IeQ5@!o(`<R%v#n`GO&I3KWR*(JhoO
@y^E;y#L>BQA7A8H4j$Lp{EnOi+YJK7sRzMN#iuf`QTKD|+6TEE)XPKd0NXnpfZZEuV1}hBh5VW2
K;U@~*uxe0<0^ou{U`H3j%+e3>jdzh{6Qq@-UYTZ@%8qQaBQ`Dp$G1rCM<AO`ah>X3wNEkkQ&OyS
;FlTGFuQ_b;bxpR1h6H<ogCi-#<XD$=F7ePWyRZ^AE+&$X~59kr;(RwiP1t4syj9+#j8Yu>7d8i#
2LWYbY$gLV$2}>%KP=@G3+}vF3DbS0Z>KdpjhxtP^CC)1P`eLF4PRVaZA}@%#z9Io~)B`z!-y<I=
4IC<-t|G!-jk9j%jLTn(D4;s=J{nvlvYSh)>Bpbk?P*>ROAT*AxdL5bdCSJWaF#03ygW19{g~?^f
nr&CR%3AGH*^iiMKx<s36`hAuCZqlUlW9rK{wy|T9rDMCYD&<E|ktJ1k<VK}E+-)7C5GP1^(6Jc7
UCS{{I5!>Kwf@9zs9a!>EiEsXGDCuOi3YN$TYC&-x$&}KPtC|7PP)Br8t)pV@cY__&oK=%aHfe!f
nGhefmGExscS}L1xSxTpFr-`r`0a*#bu)k`r92HW?=C*a@jK65u}L-AM;<T=Cdn1$fk1{2+n?xbg
g&Mn5=F|TlXH0cseb7>=uj-&q&e<r7pO%C=|U1<(PK{NEDNjjw9|}z4KXcri}l~UHQ2u@{|9Oeu~
1t-S;B!hv6&tz_ykGUw`CrQdzaQ5ZQDMS6<|VPJMB)BNOKoIc(o>35z;u26zM)ac<4HW!a&e?df!
Mt4b!=T7w#FCD^LrGV*Ax}iJ3w2qn@{G1g^myZF0PZi>@O~H|AUrW&yA@)2XO`KqOOq5?&B$*5Da
p5RA95TEmQMxjLxvnr|An@cwq9TEyH_?tL&UiqOV9<NHxS+dNPxfV7PwAx+GV$8bxGDR@0xU@REC
zr!?X6h@t!OXW6kk=^Bdt#=J99Lq$Mn~;Z{%NAKI(+Z}-A`~@bNjjsrO-I2Lh8?Ox@(!=4=R|5!3
MOTfUOrhyT%?`GcOj+HCQjbb5K;#^dHW{D#y{|ka?9{E`oyzyB@rGTN&Ek44n8aV(wHvsK-49%DR
ha2oQ~V<WRX|Ab5YH?St92Os%=(mH9R3K_!zH_rqS$j5|QmopMJwJ-5B)Eju_f$bWTYO2Mi_BK=*
dp6=oxdBaFMnG;)%`){b!O3SaW&Y=+1VnAx?m>8RJp9`X#jbgPIYLV<y}q<uKyG4}w?)x6QVU;?l
;P}}5&J5feA@(q=-+&Kx6-FC;N^*owVVUNx;4w7zq*p4QXa3HJC*FCy{hddw@dEcMBdv*N$#4_l$
k!&6<*lSzum0CWXOO6s=537dDt<!tNImH=eaQY==U*t3@kFEU#l93t%ri5P2>5*39dhLnSR~k99U
Bs@iz5w~I3EvWP^2#z-g|ap6-NqMXnt*K*%QHC;;(Jm|eSn=&b1c~UDkgDa^CAi)W5p40{$)z>Ia
%?&c9u=s@x9AMDWYdMgH5c(P#t?D&itn9^_gvu)h5PaQ&YmWO(~ZcjNxMEyRW|bD)`~#_{GWl06w
x-=CIf4@F#lx)5-g@)3<NT`^VPHH*a5@obfA5n@i~5)I*8WCCKW?j8_cG$vdaepTHy+$TUrU(`F*
CxJfBax5q8(4)BHpe0l7aMIDfVI4Z*rO>2R!74afXGDqn_AXB<l5+eYKAG8my*8gG*_ri9m1+?_Q
q7K8HrcD6?(|weV>F-MZe)1?dP6Z3m-<ACRB!BO;BA8Zu*DN{g;*<BM$FJO_o8i=xXgbnZicZaK^
;o!f_MO&GRi1J6{lSE98gT9EOq(qnAwO&fM?7N3Bf?^NV~DhRVEQt8Nq2p|Q>sOGMz!Do6hA+GZX
xpLuncqvXpsFzUm11#{LXB1`sy<l4nOm|QdR%g>odA8WacXc8Y47^Bs19j3p`JGgre^z0~&qRtGA
l6UiiF&B1L*OB_!Yius8PZ_riu@ak$8~EYtAMGFWN`{~3fOUd!65GAdo(9=J@(J*EAsGOy&5<6^}
pxy{9eA+PS8D03`481NhVJzVb+>!5{<OSoUyX;wS<-s+;!T-WR(rn$3e!Jyw8mM*%~d_0cEn&yCo
GoBFeghM|PC7#o&Jm!Sy)wHGWs7UHlPoc>{cW7UGNn;&8I66QI<w=*HbQ{QKo9b3u-3s1MS_9EgS
}8Gl9@Xe<qUaNc>Q@nW!qv7?mLWmr51*O}x$gC+mHy-tb^rA1=p(PA<r+!JwxMQM*X(Ynsi37<RR
uJ8U@sKu`72bu?d2`s0Vw6ao97(gcqp=@Fz9q`KrS23#)RhF(*7yzuEg>dfr|n}3)*e3>=9R31^J
8L?$EzLeXuz6(s^+XXXl&mUsZ5E^K81h<}3FSbmU#`+}LMxEd$H@Ha-N#enQt?rBv}$1-IMY=DTP
Z5J*O8yl@hMS*^6nu{Fz^g3*3bX4l!$2U{BO@6K?jjx#>qw{u`G-D{N^=2`q}TPG7aw+Dw|u-FU4
fs;2cc=a1~b`y7=-9(g+lZ2k3qXOOp3kO(dOTiD?WLXZ~UZ5c|^EEUeRO8E2N6F21)^s;3_o_`?K
{)L3s&?BO+716GLUY~e{RNs*n?=ijD6ye;uC}ntDEV^EW{!F2S<3Lsff$MotE^<$q8v3`DUxEgzz
6Q>itPWZ{F8cG7BlvK@+i3;8EZA$gwG#ILs`v=rv1pbxw4va=cG!M<^oH7lT9aRZEwVHT<Ds<%QN
D3_;T{Wf^pdu(>2#<Wb`Uw&IANUtNU6|pjqqC%nr+zW>xYCVOzDnvSqSO2*_SQv)Rf@04tdRvF`M
!WbS1~B}Oen7wq)30)I5V5Nyk!-O~!5yp4G)ComtYGqUFe9)>J@M%hPW2Fe1!x$A{NygwTEw6r${
-al){j#ycz6-YL&bBxc@S8YWBM#l%pu$~X?fiAO*-3OEb5MB~Tq>;X3FBI|>3G$n43B2~Dk|XHhk
!1{FthZQSf`Bi9EV?9Pt<W*SO2m|#t;0zQhQCe`wse+4jW*u)EkgH91hj=Au|YZY<7X4+0f+V&J(
k?c_DbB+WK~*j?L1Sm`P29q;%hhpouQL<QC<vq%0q*aY@S|e3Re$IZGhn$R+Zsh0ZSSXKUd?iz?q
K(Ts&3wA;Pt$%K&Ahm#Z1snqje{U{fq8LS__ngO8RJbVU-SE8aADk<I7$0fw2~0nfJoD41!32X1d
BPEU9<%U()o)j-$?B!RwR^ugTqZ3>p?XOhNvy4mK$)2WyPME9X(iLk1$D)L0s3R9%o(+$q3XgMv8
fQM{&m!B{+8Zr_TfigM6$;h4%5PVilQFnwFC8U4Q?!hV8B-0n7KF-`J1r8eT;qo_C+kTK+jX&~X*
G42-*zVA=_YupTD)T8r&KSE$K||eFm{w9l8<|$uiiayT$%V;IXn}Wm>YaD5WHwgGIFf6a{U>(<GQ
}j7dVPQPwxJc<ud5cwt!z|f)?23ZzyZ=88Oi9xC9P31EX<?ZcogL$WOvZA(3lsR?i`K}D@+s}a>|
s+%9_dMxDU)U^7%AD4R@Jctgxglla)rpp%7?bs6oPB9Ud-N`gnh7>-ouzFn^G@sW*TO&d;~AH7p5
vviOI`A2jBxMxBb#44Q{pUu;`*KKJs)pM?OJoe5yRVRe)d!nAGRN+45ktym&-ap8F(sMxg%w&Zj*
B9oYrGz&m{`RwP>+4JL97~=9(g}as(;MfP|H~S{4sf|>BZ&cAwB@Vg6b&Lr*EMg>>-VzafG-BJ=5
pBWINP8@x#~LtfMaYr}x^w^jzX6ZY(A@
