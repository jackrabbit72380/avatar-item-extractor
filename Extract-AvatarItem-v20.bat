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
rem  It needs Python 3.8 or newer, and once only it needs the two reader
rem  modules - avatar_mesh.py and lzx.py - in the same folder as this file.
rem  It copies them into its own folder and does not ask again.
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
echo   Item sources were found, but no model parsed out of them.
echo   The reason is printed above, one line per item.
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
"""Unpack the code carried in the .bat and run the extractor.

Written out of the .bat by its batch header, then run by the same header. The
payload is everything after the last ###PAYLOAD### marker: base85 of a zlib
stream holding the extractor. The two reader modules are picked up from beside
the .bat and kept in the same folder as the extractor.
"""

import base64
import json
import os
import shutil
import sys
import zlib

MARKER = "###PAYLOAD###"
READERS = ("avatar_mesh.py", "lzx.py")


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


def main():
    bat, cache = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
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
    status = ensure_readers(cache, os.path.dirname(os.path.abspath(bat)))
    if status:
        return status
    target = os.path.join(cache, "extract_items.py")
    with open(target, "r", encoding="utf-8") as handle:
        code = compile(handle.read(), target, "exec")
    sys.path.insert(0, cache)
    sys.argv = [target] + rest
    exec(code, {"__name__": "__main__", "__file__": target})


if __name__ == "__main__":
    sys.exit(main() or 0)
###PAYLOAD###
c-qA~4RhPLv3~_so~Pu5qV02<xu?c?<4c^@(_E5qa@Vw$pN<kCi7`d81Zi8nroX-W0f69#EZ@7Ed
AbjaAh1|0_Ip=9kK}z-MvH2eRC1%jVmq3Qp8W2xR^{P5$qr?9D~fHk&a;zgHXY$V=e$6avWk*ae4
gj`;^g^}h;E}QDh0t2Nmk_|5(^kg^HnWHl*OWu<rrU!Ws*u20>JE5RF;X1VZKUYDKzZy8Ns@Mx#Q
b!j>36Vi7H>oYAs7~msD#3-$Zqn0}@dTW1Bp#0pv7GDv?PUt3ceXlf_y@r4)B%QdKe&b4hzt>qH5
)D3hWRc?P(Y3Jz0eq4=wwm}H_zqXf`9`}peO0%sL<S>#GiXk$PJK;t3AA}<oDa8$wgwu0}svV;lA
hR*l5ycTgTvK$T|(-f!!h{;kC93~Z@7>bKZEY@;y1CIds9w?F~fL6XlOcoN(Q$;s;KndWtv{I<NE
*A&|R%Cc&q_MtEfCIb1a@c1Rig!7jI$H@id8BS+93VzG0u)oCNER>#=!-Rgm>}K)KF1-`YMG}<V}
y=ao5y*6i<|S@Z$feK!^iW>50~%XT)aI$n8N3EewU?r6f2%`GBic1n<_7O!m~jbi+UroO2hcWz?A
oyd|f8Da$w8n`=*=i;ikoO!~~s=h)m|3YxsktTcmLRASPKX@54&n3J-~)g&>W#d0kBey$z<>i&dS
(FGG-^KqQMiQ-{9DOJF2v;o(bhD8fhqSmB6;I1>scq_P>DW>KngahI3KAn<Pn_gtjO0`5L4S45#u
d;m~lJT7x&wp=I~mB6Md-$-UTnJO6|8qqW>A`~K+bdwY!PSheNz5+N&Dbp?S?pekdXbh1iKYjdk`
Q1;z^%)#HlVvErOY_BzIKkIQ4-iC|GAF|EG<667TuHSCIiAx3nEv+fpU2BG+BDLS04(Uh5fm9GRb
KvH3AkQ{h9>|p3Wh=C65w}&t5|SD@iA}Efz2#W>shC;vYgNO$%{eR`24<zw#Yv)f$==i%TVGau0w
@0Bd}g97x|`u{gtPe`9AK$nrEBH6onF$9xtDuW~dSp=KA=#sLCYbYtCXG{ozM}gbKtaswBKkr&$S
mlp4$!*UNkHB?s-Qh{ks^S*>w}T9Y13j2bZN1!y+UYtRmKqd%x<B`5l%q}4@N{fpk`38@!BiidPY
U=~^F-v#Rh%g{J4$H>Mn0T%H9%7GTP2iI$6emy~9jq6R(9@)U<<FVcsRRS`m4>lfyD2mq?m*xPPk
8&~uQoy|}qdEm?)%(fVw=3sg+@rJ9(JC3iofc84fL)oZKn`EPPA?A$-NP3s@UY&3%F?a4c>S+;XW
yU0fFT(TZ;&5IAIAy>G6N}4!YgGVffeVev<Rii24wu5K?wN05YZC21IB1yGcn7@q-gX+ZF9gpZCL
@Cc}zY_9IYf=JrBZI0h4RvAvCqv9u1)gsISLyQfjD;)V6K2Smh4s`?i=w2Q9EP7s=GME=2f6<up$
0!-7H5g>;w@4N-E`4Tt~>b|6*~v|m+jU4X2Q>ADKI0{oB_j}djS^dQin23spy7tB0`P6+V}qJ4f3
m!ztws?|gsk;-Lz%M25Meq?q>B7-!FIdG`9z;@2F#wOFGP+ZD?)Cuah4=f)i;kQrGmLu89cnk}xt
w22pQcVI*{uv^aY>K=j+d$Cm0Fux?<jQ_6n<;8tS4rADZWRK&c=!7JGpN7msA~st!;4Sn-_OoJe>
#8n@#6ivk1)@hj?lnOM*%Eh8#f)n6@UE8#fKR%3eNd?I?6zjX2yA=xwBcZU4X2~*-S59ftI0fw=#
?KlD}Kgg-5<B`<agZ>+<~7-(I~v55K#3$J0M<6<V?%^Av2QxBvo|AcLSZrlYUZ?EACNv)AVzKK&V
xLN^zVwiKw(XUN;0F|{*b^3!*~e7<H-ruT)WHMy*`0#sLEy-rj{BuXe@=rUT?mzwiKb8iTfq~{dw
CPWh*!j{O`o_UVu3jcbu8N!;)d@Y6xQ2GhjF|tut*F2akg^T;7AyhLxjEVy2+B#$(=2HM_P(btJA
)4-;_yJ+AHwN+w@-V;$XrMUz)63?R=2ZAUznKO2n;G&R)Q|F7IN&$Lp-p+f#h<iU0(h90focO2>K
z55vlD(mO?1`~4!zs$&jB~5F0<Wp<o!ZIu)&OSUY6*BDI6Wx&*EC-g?Ho+Y!)RDYA{2i-toEwK%y
Tg&}nrVlM$FpeF_;*;Emz52R{cwlNYcwJl5YiYh<p21MaI;T~E`4VyiRae+ulP6?kl7S?1tr3Kuz
W$N_JV7~&RHV>qY8D>D6`@;p`K%ognR8Y>i%n!$gb!0500G>)-R3fg|n(26Rrtp`3~Y($}(HmYbb
L-D>OBN%})C>5K36c09#cq_k!_^-j@ILknoLF#H?cHoYG6Gi9(5o^>B4UI{To5$|H_}U+M&pIIAk
Pc{quF?LvI^uf7OdI*_pKD{f(J#fPv$Bhw)@M(|jg$r5Szacq1j8}mkq_{1!Ndk9lB{}Mf`=B@s7
y(7qBG7;6I}k%fQ!)T!{NZgL@#Meyn;@E${o%CFAgA}C>15R{A@DdT0m7vOn)TCe^wF<O{4dbzsS
$S5Df3!(K9sO*St8~*1Wi_nUyGD2%ghXSs1P*SuI;jqipN(KCltxY&1e4_()}?kZ>Nqc#3-{S@?u
Bj{(+rp#59nEMvc%188-OZ&?$d<R)syE||w|ZotvD*#xj=7Y9`lzHmv#@IIAhZ=>(wn1(_ME*xUB
%0sd7ua2+7G`|D!^ATXzJz8p)-)`nNcw(%jF;#RZ)z&iS6sK!f9rUZzs)R(Ff-6igC=L!FJVzZ2D
hb&TWBmeM_m;+CE&Vv=`4wz2kCdFnU<TK_xGyXrCQk}aGeigmEUU~@0|@b3)Fnz!01CQP`X&)yn0
yzdH-jkQ)T_xghW=y<y_i5zo&w+PF^c-=vCG2XoPw$#+OnkuP}afim~L})jrxO!6=R27Z7|7FLwb
2CtlK)^Ml`22_v%1sWWf@$B@FI|LlG@xdb<CZ{pu|FM=d*yWt>8S+GZ?zrHROEJJ|4`LB(<4v^et
n-^%u*`KKfb#yLhfDfvSqT8p%0Gl|9crSMSkufR@VN@t$O^q15EJ2~9|Dm1yNH*hBcV(T&RKvV*d
7~}{7mP}1-K1clNhl|$%XUce+t(YejhP^xr8|rAc8N<y(@rq#StT_g&oVO;3zgIdBzC;`-k8LvOi
I$8eu77*+<2h*8@)qn57{;P<(Sg(cQKJpRXr~N-pV&qG4iNmbE#yxo!FM7yGRhR-o64t4iGN6>jt
{?~Hx%yUu_y-<x&${lyOvTR`)-sxDRs>!z`2MXMxI~wnb3mgz)v=opzu;=iyU*br_)hgEyv%|7`p
8WM!+;<MxF#;QNlcRITg7)O)}E$y_bw_Nlq9}GFkvmg3-IrW`rIq>$N#Dk`kt{-WM;#vjJ)C>s?w
2j1%Ambr=$`AZS-d*Ma_aY`=YDznxq^CQxebAHagQ;_-gR&j+*x-sTMXQ%^NW9d`pB9Xb6NrM0BM
>CtD_mwkn2N43<IO5R@!W=oIgm5oWpT>h+C?jguo68F9Tu0+Be-?CwPK+ammm=c4OWe(}92mJWI-
qq3gzoYT;Z2ac>=WoCIW8_DJL<@DKC9MlrWnLHFu}>F(tizD81RyYl(VPxsHI<9XV~a50Y;cyU%5
4ghv{;kEod_?91F=i%=~%mU%tjKOR7K-epfT#;W7rsu?1;Mcy37EYO$uD}Y9Cm;=g3`|8w_?{Z9q
f{hzx-~r+;k}^`5*0PdB>9?<fbmx7Qa)@)osw;@BF!e@H%^*Gq3`Y8uPfoUXq?@UWLNcnm}Kr^4j
)eBbX8)sY%=Qsd(40|9W1a?oWow=-$`hg4XQnM(3(=#m{#wb?B_-Fn;Ff#`VLd%e>x2^pI%ci?E7
HFlG8kd$-+e~-F}C8kN{()egYf_aAWHzqq1Ey#Do9OE6j|B<N+-z8}(R-l1I-BvP>ku{CnbaYIvV
IU4-R#(%JIIzoCvQo)E?fPFS9d=LH%XASqJ{WF{2Cy#}CSOT(0RO(;c*iXc?6clLqHihwFTq^<GA
-`xP!rCC)^F#QT368U3mkV7m5Gub=D;8(!fIxVTP~@blSy4E;mRfzaYT{U%2r7zpQbA}SZl$~f(X
tLw*y9MFQD|j=7<U13+;<?!NnIGzPiR|Dwp9Ste|oPy?YaZE&8e*v9?QLi?ozY+)=63t^rN?K1wm
8k8y4{uS(cnStPFEE4gy;m8-xWW;lCHNXr6kDqT3{a1`qNj6OdehDOPa!ldOtWixhs{gqfzm%TH6
IBQFqf^&u(=kcnO>!C%+qh=?}t(<6O)Cit|mMD7hXgXje##Fqyv4LxxG~~NU*&+Ivtkxx$`!%xId
NW+($0mY5whQ}CHQzw%7WH*<4AaP!Ebxe=?>5*M16oh_8j$dzir_@Y5O>*HKJkuI(5L6&s{a22$L
WlNM)#LprR^=ys~>lR1veG|W79WgLGl}s1vS|yjHlOT@CwU7+}QvqXn%{l4%*4)s}cvj4c2b1BCr
k2<pnid(cZw&&)`2jFS>tl-gVot!iki$f|E<{#BXJAyEG&H<y0CPy@YALz<p&&$ZAeM`mH(5`FWD
T(w$@OgeIYlvd{o8-2(!c`Qq>pgm8%VZFu$VjM{1d8d8eD)wllcTdQx~E30p5x4_giPLDe1f;y_p
-nl{bpxO7_3Dnzkb=_Xi9Vy^AvL!Iv+F`teAyls&C{M%%HM)Uz0FPlS>S7|6QdUA?<5LAAr{c)=y
R6a7Re7PP=9<Z<6vyH7uyvQjm86~No8Ied%ZO{qF!yd9v%4rmKi0a}9Nl2MVLOqGQmaQF$|A3$t*
TJ%L2&B&*!b^LLB0pl6%DWN8xN$HfaZ-{2gSlA4~Smlu)*^;Opt*y0+cT5%1~$nYTAp+)orUxPO?
?PF-<!{c&2;SKF}Mdj>x_*wey@dou+PQX(;}hP@>Sdxu*Zk_CbnW1x{euHE<Ky6`3yE&5})XlLZs
n1PtRJMsYkdn|V#MAo4-E!pzYB;DeDS3KDjQ2Wy!Yuq3CWM(KpyGo97fje^#V#Mrx5(lqAm!3%EW
VWjNdbaiIa!LF!>ccMls2CpgxIO797ZqNPT=U)&KAjAAX{=uw52^v|DPJ5Q^%c4H4z0k9C+XBzQp
Nl*CuizO2|CR7wH*-B0_GzSA-CnIGFWuirDHZf(S{+sUP^NA$M6lWx@-(3eh|%7bAOk&O`{0`9vH
jHU_m%B~jkTCZkl7&5rE^LQ|02?u`oD{7Qp!b@mu|tm)h%vdqNs2#6hYG;1g=Px`Nlg!qe41Ng$<
`uJFOmKZS8a>Ir$=*qw{4>0aG`HftTb=xOOX?NDk@N=P-pg8J;m%R%;dXJlckyu=dsNW^f%UDmVj
S-{$!Z@+vu4?FRozD?{z>VsPqazBNoiO(+l<cZ$vpHCjbb1Fc`4)-!f&(@UV67p56rciEwWGR=;x
n3QgA=Spg{6Hu=u9Ep@|skQsC-`Kqq&WBo;PzYYrhbbD&Hrz;1XWT9m?1a^H#L#W%4&0ah&9x8lt
bgaNsb=sEm5EJugDHOiq{n+C*Hd4H&zUh(tuUh)t{!vx8H5}?nl|g0-!f!-E){u42=4&=7~0unlX
fJ{e1FIBbh;gs29{!Ms~?F6eskL3h~M$KTVn!|$HTT&EGfl@X1A0k%)s~+tEW7HGG?><<`n%zzpX
yNs7+e!EOx0yaVG#27Xp&yGeTh(B!hk*l5st$A>FO(LfDOQfHQ=x7wGw8ybG~{tGZE9aicQOXZ~f
zwfj?UPN26(ZVve&zG$ilof<|@QRtZu@f6Ft>B()X9RXv8ZMn#BgXzP5KDm|Xf4DM&XB);(BR?E=
Fh_uU;Xl3%sQHL{%2A(iI+ZTe$Bu&L^#IU0SkIe&FM*C+bkh#r`cPM+zTKyw1s;p80f)BUYsy`NH
0mUrsp2%$%%EAdUn-%j$w522ZHq|+&i5aS_&`;8zN=hp10OK0z{vcba#CLJtnIjz6W#sHZ&%Axn|
v$V(ZoZXyfj1@nt|uXIc_vMII&@JobIsv&}5bZ4#VSJljw&}FlG2U2A7zaY|?9Fq&0kiaK{O3GTW
wldEk0@woP*PGQ)%OZ4$hji5i@Z8WJb(h$6wvV}LXG{_B8<^mB+#H-g$Jm&1mq)d~RbWz{uxjyY-
-58bG&|0|=*CV|VzW78YC9oxK*$@v7F>>0@MxF5>YQhYdrtvyE83Q!>GVundW2o<(F@nQkG(iG<e
EB_wkK=FY<W9U;3LujmApUNF)e!rgTa*xi%>HIJ1nmW75@;g(d9n_Y)905BG#<e5W^J0eN%JFMDH
(sFGe7M-ARkpLIzk}KMmnk8}o>aATmINIJY`mBOboSje3!lDf`mqpPb)g-A2d|nP8@}ctJ!~(OAB
P)!tU*2ye>gfq$N6YTa2w}ES4+b%bZVpw!*W3LL+noC+eBBCl-A$dd0h6pD2dw*F!g;6durD$Fxp
F=7)rD=ufuvoyUguhfLVTO%&ZaY>F92_eQVhEBD4^HRp{9r0zE6BnsZj29$O0bq9Ze4tJUTgKb7?
)JohdFeM-Nxo^FujS+P2%Vmq@E|1gaP=%;78s_e1@{ZfN}K}KtWM&bC4|F0deNk1H-?QO$4C9Cvg
c6j-F1Ig&7ouCr#g(ajWmLtuwZs2D%o2fZxc89CU@zM28pPeH?L+B0|za0a#5D+iL@zDcdL5|2dr
dugxbCC^%F?Oo8bMZ%9ekE&4VeSbh+F^7yLsdDOp(x`I+%QXyzi!hw;4gk8{+x!g=LmN6^*@Z*gj
)
