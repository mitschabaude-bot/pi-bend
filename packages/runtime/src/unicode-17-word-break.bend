# Generated from pinned Unicode17 UCD by generate-regex-unicode.py --word-break.
# Unicode License V3; see unicode-LICENSE.txt. Low5 bits Word_Break, bit5 Extended_Pictographic.
import Base

def propertiesBelow0(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 2
def propertiesBelow1(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 1
def propertiesBelow2(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow0(code,U32.is_lt(code,10))
    case False{}: propertiesBelow1(code,U32.is_lt(code,13))
def propertiesBelow3(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7
def propertiesBelow4(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 17
def propertiesBelow5(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow3(code,U32.is_lt(code,32))
    case False{}: propertiesBelow4(code,U32.is_lt(code,34))
def propertiesBelow6(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2(code,U32.is_lt(code,11))
    case False{}: propertiesBelow5(code,U32.is_lt(code,33))
def propertiesBelow7(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 16
def propertiesBelow8(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 14
def propertiesBelow9(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow7(code,U32.is_lt(code,39))
    case False{}: propertiesBelow8(code,U32.is_lt(code,44))
def propertiesBelow10(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 15
def propertiesBelow11(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 13
def propertiesBelow12(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow11(code,U32.is_lt(code,58))
def propertiesBelow13(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow10(code,U32.is_lt(code,46))
    case False{}: propertiesBelow12(code,U32.is_lt(code,48))
def propertiesBelow14(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow9(code,U32.is_lt(code,40))
    case False{}: propertiesBelow13(code,U32.is_lt(code,47))
def propertiesBelow15(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow6(code,U32.is_lt(code,14))
    case False{}: propertiesBelow14(code,U32.is_lt(code,45))
def propertiesBelow16(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 14
    case False{}: 0
def propertiesBelow17(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow18(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow16(code,U32.is_lt(code,60))
    case False{}: propertiesBelow17(code,U32.is_lt(code,91))
def propertiesBelow19(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 12
    case False{}: 0
def propertiesBelow20(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow21(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow19(code,U32.is_lt(code,96))
    case False{}: propertiesBelow20(code,U32.is_lt(code,123))
def propertiesBelow22(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow18(code,U32.is_lt(code,65))
    case False{}: propertiesBelow21(code,U32.is_lt(code,97))
def propertiesBelow23(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 3
    case False{}: 0
def propertiesBelow24(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 8
def propertiesBelow25(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow23(code,U32.is_lt(code,134))
    case False{}: propertiesBelow24(code,U32.is_lt(code,170))
def propertiesBelow26(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 5
def propertiesBelow27(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow28(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow27(code,U32.is_lt(code,181))
def propertiesBelow29(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow26(code,U32.is_lt(code,173))
    case False{}: propertiesBelow28(code,U32.is_lt(code,175))
def propertiesBelow30(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow25(code,U32.is_lt(code,169))
    case False{}: propertiesBelow29(code,U32.is_lt(code,174))
def propertiesBelow31(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow22(code,U32.is_lt(code,95))
    case False{}: propertiesBelow30(code,U32.is_lt(code,171))
def propertiesBelow32(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow15(code,U32.is_lt(code,35))
    case False{}: propertiesBelow31(code,U32.is_lt(code,133))
def propertiesBelow33(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 13
def propertiesBelow34(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow35(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow33(code,U32.is_lt(code,183))
    case False{}: propertiesBelow34(code,U32.is_lt(code,185))
def propertiesBelow36(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow37(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow38(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow36(code,U32.is_lt(code,187))
    case False{}: propertiesBelow37(code,U32.is_lt(code,215))
def propertiesBelow39(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow35(code,U32.is_lt(code,184))
    case False{}: propertiesBelow38(code,U32.is_lt(code,192))
def propertiesBelow40(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow41(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow42(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow40(code,U32.is_lt(code,247))
    case False{}: propertiesBelow41(code,U32.is_lt(code,728))
def propertiesBelow43(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow44(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow45(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow44(code,U32.is_lt(code,886))
def propertiesBelow46(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow43(code,U32.is_lt(code,768))
    case False{}: propertiesBelow45(code,U32.is_lt(code,885))
def propertiesBelow47(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow42(code,U32.is_lt(code,248))
    case False{}: propertiesBelow46(code,U32.is_lt(code,880))
def propertiesBelow48(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow39(code,U32.is_lt(code,186))
    case False{}: propertiesBelow47(code,U32.is_lt(code,734))
def propertiesBelow49(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow50(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 14
    case False{}: 8
def propertiesBelow51(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow49(code,U32.is_lt(code,890))
    case False{}: propertiesBelow50(code,U32.is_lt(code,895))
def propertiesBelow52(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow53(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow54(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 13
    case False{}: propertiesBelow53(code,U32.is_lt(code,907))
def propertiesBelow55(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow52(code,U32.is_lt(code,902))
    case False{}: propertiesBelow54(code,U32.is_lt(code,904))
def propertiesBelow56(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow51(code,U32.is_lt(code,894))
    case False{}: propertiesBelow55(code,U32.is_lt(code,903))
def propertiesBelow57(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow58(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow59(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow57(code,U32.is_lt(code,909))
    case False{}: propertiesBelow58(code,U32.is_lt(code,930))
def propertiesBelow60(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow61(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow62(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow61(code,U32.is_lt(code,1155))
def propertiesBelow63(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow60(code,U32.is_lt(code,1014))
    case False{}: propertiesBelow62(code,U32.is_lt(code,1154))
def propertiesBelow64(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow59(code,U32.is_lt(code,910))
    case False{}: propertiesBelow63(code,U32.is_lt(code,1015))
def propertiesBelow65(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow56(code,U32.is_lt(code,896))
    case False{}: propertiesBelow64(code,U32.is_lt(code,931))
def propertiesBelow66(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow48(code,U32.is_lt(code,216))
    case False{}: propertiesBelow65(code,U32.is_lt(code,908))
def propertiesBelow67(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow32(code,U32.is_lt(code,59))
    case False{}: propertiesBelow66(code,U32.is_lt(code,888))
def propertiesBelow68(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow69(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow70(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow68(code,U32.is_lt(code,1328))
    case False{}: propertiesBelow69(code,U32.is_lt(code,1367))
def propertiesBelow71(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow72(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 13
def propertiesBelow73(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow71(code,U32.is_lt(code,1373))
    case False{}: propertiesBelow72(code,U32.is_lt(code,1375))
def propertiesBelow74(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow70(code,U32.is_lt(code,1329))
    case False{}: propertiesBelow73(code,U32.is_lt(code,1374))
def propertiesBelow75(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 14
def propertiesBelow76(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow77(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow75(code,U32.is_lt(code,1417))
    case False{}: propertiesBelow76(code,U32.is_lt(code,1419))
def propertiesBelow78(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow79(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow80(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow79(code,U32.is_lt(code,1473))
def propertiesBelow81(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow78(code,U32.is_lt(code,1470))
    case False{}: propertiesBelow80(code,U32.is_lt(code,1472))
def propertiesBelow82(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow77(code,U32.is_lt(code,1418))
    case False{}: propertiesBelow81(code,U32.is_lt(code,1471))
def propertiesBelow83(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow74(code,U32.is_lt(code,1369))
    case False{}: propertiesBelow82(code,U32.is_lt(code,1425))
def propertiesBelow84(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow85(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow86(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow84(code,U32.is_lt(code,1476))
    case False{}: propertiesBelow85(code,U32.is_lt(code,1479))
def propertiesBelow87(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow88(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow89(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow87(code,U32.is_lt(code,1488))
    case False{}: propertiesBelow88(code,U32.is_lt(code,1519))
def propertiesBelow90(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow86(code,U32.is_lt(code,1478))
    case False{}: propertiesBelow89(code,U32.is_lt(code,1515))
def propertiesBelow91(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 13
def propertiesBelow92(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow93(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow91(code,U32.is_lt(code,1524))
    case False{}: propertiesBelow92(code,U32.is_lt(code,1536))
def propertiesBelow94(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 14
def propertiesBelow95(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow96(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow95(code,U32.is_lt(code,1563))
def propertiesBelow97(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow94(code,U32.is_lt(code,1548))
    case False{}: propertiesBelow96(code,U32.is_lt(code,1552))
def propertiesBelow98(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow93(code,U32.is_lt(code,1525))
    case False{}: propertiesBelow97(code,U32.is_lt(code,1550))
def propertiesBelow99(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow90(code,U32.is_lt(code,1480))
    case False{}: propertiesBelow98(code,U32.is_lt(code,1542))
def propertiesBelow100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow83(code,U32.is_lt(code,1376))
    case False{}: propertiesBelow99(code,U32.is_lt(code,1523))
def propertiesBelow101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow101(code,U32.is_lt(code,1565))
    case False{}: propertiesBelow102(code,U32.is_lt(code,1611))
def propertiesBelow104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 14
def propertiesBelow106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow104(code,U32.is_lt(code,1642))
    case False{}: propertiesBelow105(code,U32.is_lt(code,1644))
def propertiesBelow107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow103(code,U32.is_lt(code,1568))
    case False{}: propertiesBelow106(code,U32.is_lt(code,1643))
def propertiesBelow108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow108(code,U32.is_lt(code,1646))
    case False{}: propertiesBelow109(code,U32.is_lt(code,1649))
def propertiesBelow111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow112(code,U32.is_lt(code,1758))
def propertiesBelow114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow111(code,U32.is_lt(code,1749))
    case False{}: propertiesBelow113(code,U32.is_lt(code,1757))
def propertiesBelow115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow110(code,U32.is_lt(code,1648))
    case False{}: propertiesBelow114(code,U32.is_lt(code,1750))
def propertiesBelow116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow107(code,U32.is_lt(code,1632))
    case False{}: propertiesBelow115(code,U32.is_lt(code,1748))
def propertiesBelow117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow117(code,U32.is_lt(code,1765))
    case False{}: propertiesBelow118(code,U32.is_lt(code,1769))
def propertiesBelow120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: propertiesBelow121(code,U32.is_lt(code,1789))
def propertiesBelow123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow120(code,U32.is_lt(code,1774))
    case False{}: propertiesBelow122(code,U32.is_lt(code,1786))
def propertiesBelow124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow119(code,U32.is_lt(code,1767))
    case False{}: propertiesBelow123(code,U32.is_lt(code,1776))
def propertiesBelow125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow125(code,U32.is_lt(code,1792))
    case False{}: propertiesBelow126(code,U32.is_lt(code,1809))
def propertiesBelow128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow129(code,U32.is_lt(code,1958))
def propertiesBelow131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow128(code,U32.is_lt(code,1840))
    case False{}: propertiesBelow130(code,U32.is_lt(code,1869))
def propertiesBelow132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow127(code,U32.is_lt(code,1807))
    case False{}: propertiesBelow131(code,U32.is_lt(code,1867))
def propertiesBelow133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow124(code,U32.is_lt(code,1770))
    case False{}: propertiesBelow132(code,U32.is_lt(code,1810))
def propertiesBelow134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow116(code,U32.is_lt(code,1645))
    case False{}: propertiesBelow133(code,U32.is_lt(code,1791))
def propertiesBelow135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow100(code,U32.is_lt(code,1475))
    case False{}: propertiesBelow134(code,U32.is_lt(code,1759))
def propertiesBelow136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow67(code,U32.is_lt(code,182))
    case False{}: propertiesBelow135(code,U32.is_lt(code,1564))
def propertiesBelow137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 8
def propertiesBelow139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow137(code,U32.is_lt(code,1970))
    case False{}: propertiesBelow138(code,U32.is_lt(code,1994))
def propertiesBelow140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 14
def propertiesBelow142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow140(code,U32.is_lt(code,2036))
    case False{}: propertiesBelow141(code,U32.is_lt(code,2040))
def propertiesBelow143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow139(code,U32.is_lt(code,1984))
    case False{}: propertiesBelow142(code,U32.is_lt(code,2038))
def propertiesBelow144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow144(code,U32.is_lt(code,2042))
    case False{}: propertiesBelow145(code,U32.is_lt(code,2045))
def propertiesBelow147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow148(code,U32.is_lt(code,2075))
def propertiesBelow150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow147(code,U32.is_lt(code,2048))
    case False{}: propertiesBelow149(code,U32.is_lt(code,2074))
def propertiesBelow151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow146(code,U32.is_lt(code,2043))
    case False{}: propertiesBelow150(code,U32.is_lt(code,2070))
def propertiesBelow152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow143(code,U32.is_lt(code,2027))
    case False{}: propertiesBelow151(code,U32.is_lt(code,2046))
def propertiesBelow153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow153(code,U32.is_lt(code,2085))
    case False{}: propertiesBelow154(code,U32.is_lt(code,2089))
def propertiesBelow156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow156(code,U32.is_lt(code,2112))
    case False{}: propertiesBelow157(code,U32.is_lt(code,2140))
def propertiesBelow159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow155(code,U32.is_lt(code,2088))
    case False{}: propertiesBelow158(code,U32.is_lt(code,2137))
def propertiesBelow160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow160(code,U32.is_lt(code,2155))
    case False{}: propertiesBelow161(code,U32.is_lt(code,2184))
def propertiesBelow163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow164(code,U32.is_lt(code,2208))
def propertiesBelow166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow163(code,U32.is_lt(code,2192))
    case False{}: propertiesBelow165(code,U32.is_lt(code,2199))
def propertiesBelow167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow162(code,U32.is_lt(code,2160))
    case False{}: propertiesBelow166(code,U32.is_lt(code,2194))
def propertiesBelow168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow159(code,U32.is_lt(code,2094))
    case False{}: propertiesBelow167(code,U32.is_lt(code,2185))
def propertiesBelow169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow152(code,U32.is_lt(code,2041))
    case False{}: propertiesBelow168(code,U32.is_lt(code,2144))
def propertiesBelow170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 10
def propertiesBelow171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow170(code,U32.is_lt(code,2274))
    case False{}: propertiesBelow171(code,U32.is_lt(code,2308))
def propertiesBelow173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow173(code,U32.is_lt(code,2365))
    case False{}: propertiesBelow174(code,U32.is_lt(code,2384))
def propertiesBelow176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow172(code,U32.is_lt(code,2275))
    case False{}: propertiesBelow175(code,U32.is_lt(code,2366))
def propertiesBelow177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow177(code,U32.is_lt(code,2392))
    case False{}: propertiesBelow178(code,U32.is_lt(code,2404))
def propertiesBelow180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow181(code,U32.is_lt(code,2436))
def propertiesBelow183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow180(code,U32.is_lt(code,2416))
    case False{}: propertiesBelow182(code,U32.is_lt(code,2433))
def propertiesBelow184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow179(code,U32.is_lt(code,2402))
    case False{}: propertiesBelow183(code,U32.is_lt(code,2417))
def propertiesBelow185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow176(code,U32.is_lt(code,2362))
    case False{}: propertiesBelow184(code,U32.is_lt(code,2406))
def propertiesBelow186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow186(code,U32.is_lt(code,2445))
    case False{}: propertiesBelow187(code,U32.is_lt(code,2449))
def propertiesBelow189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow190(code,U32.is_lt(code,2482))
def propertiesBelow192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow189(code,U32.is_lt(code,2473))
    case False{}: propertiesBelow191(code,U32.is_lt(code,2481))
def propertiesBelow193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow188(code,U32.is_lt(code,2447))
    case False{}: propertiesBelow192(code,U32.is_lt(code,2474))
def propertiesBelow194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow194(code,U32.is_lt(code,2486))
    case False{}: propertiesBelow195(code,U32.is_lt(code,2492))
def propertiesBelow197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow198(code,U32.is_lt(code,2505))
def propertiesBelow200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow197(code,U32.is_lt(code,2494))
    case False{}: propertiesBelow199(code,U32.is_lt(code,2503))
def propertiesBelow201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow196(code,U32.is_lt(code,2490))
    case False{}: propertiesBelow200(code,U32.is_lt(code,2501))
def propertiesBelow202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow193(code,U32.is_lt(code,2451))
    case False{}: propertiesBelow201(code,U32.is_lt(code,2493))
def propertiesBelow203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow185(code,U32.is_lt(code,2385))
    case False{}: propertiesBelow202(code,U32.is_lt(code,2483))
def propertiesBelow204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow169(code,U32.is_lt(code,2084))
    case False{}: propertiesBelow203(code,U32.is_lt(code,2437))
def propertiesBelow205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow205(code,U32.is_lt(code,2510))
    case False{}: propertiesBelow206(code,U32.is_lt(code,2519))
def propertiesBelow208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow208(code,U32.is_lt(code,2524))
    case False{}: propertiesBelow209(code,U32.is_lt(code,2527))
def propertiesBelow211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow207(code,U32.is_lt(code,2511))
    case False{}: propertiesBelow210(code,U32.is_lt(code,2526))
def propertiesBelow212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 8
def propertiesBelow214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow212(code,U32.is_lt(code,2532))
    case False{}: propertiesBelow213(code,U32.is_lt(code,2544))
def propertiesBelow215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow216(code,U32.is_lt(code,2559))
def propertiesBelow218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow215(code,U32.is_lt(code,2556))
    case False{}: propertiesBelow217(code,U32.is_lt(code,2558))
def propertiesBelow219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow214(code,U32.is_lt(code,2534))
    case False{}: propertiesBelow218(code,U32.is_lt(code,2557))
def propertiesBelow220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow211(code,U32.is_lt(code,2520))
    case False{}: propertiesBelow219(code,U32.is_lt(code,2546))
def propertiesBelow221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow221(code,U32.is_lt(code,2564))
    case False{}: propertiesBelow222(code,U32.is_lt(code,2571))
def propertiesBelow224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow224(code,U32.is_lt(code,2577))
    case False{}: propertiesBelow225(code,U32.is_lt(code,2601))
def propertiesBelow227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow223(code,U32.is_lt(code,2565))
    case False{}: propertiesBelow226(code,U32.is_lt(code,2579))
def propertiesBelow228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow228(code,U32.is_lt(code,2609))
    case False{}: propertiesBelow229(code,U32.is_lt(code,2612))
def propertiesBelow231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow232(code,U32.is_lt(code,2620))
def propertiesBelow234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow231(code,U32.is_lt(code,2615))
    case False{}: propertiesBelow233(code,U32.is_lt(code,2618))
def propertiesBelow235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow230(code,U32.is_lt(code,2610))
    case False{}: propertiesBelow234(code,U32.is_lt(code,2616))
def propertiesBelow236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow227(code,U32.is_lt(code,2575))
    case False{}: propertiesBelow235(code,U32.is_lt(code,2613))
def propertiesBelow237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow220(code,U32.is_lt(code,2530))
    case False{}: propertiesBelow236(code,U32.is_lt(code,2602))
def propertiesBelow238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow238(code,U32.is_lt(code,2622))
    case False{}: propertiesBelow239(code,U32.is_lt(code,2631))
def propertiesBelow241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow241(code,U32.is_lt(code,2635))
    case False{}: propertiesBelow242(code,U32.is_lt(code,2641))
def propertiesBelow244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow240(code,U32.is_lt(code,2627))
    case False{}: propertiesBelow243(code,U32.is_lt(code,2638))
def propertiesBelow245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow245(code,U32.is_lt(code,2649))
    case False{}: propertiesBelow246(code,U32.is_lt(code,2654))
def propertiesBelow248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow249(code,U32.is_lt(code,2677))
def propertiesBelow251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow248(code,U32.is_lt(code,2662))
    case False{}: propertiesBelow250(code,U32.is_lt(code,2674))
def propertiesBelow252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow247(code,U32.is_lt(code,2653))
    case False{}: propertiesBelow251(code,U32.is_lt(code,2672))
def propertiesBelow253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow244(code,U32.is_lt(code,2633))
    case False{}: propertiesBelow252(code,U32.is_lt(code,2655))
def propertiesBelow254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow254(code,U32.is_lt(code,2689))
    case False{}: propertiesBelow255(code,U32.is_lt(code,2693))
def propertiesBelow257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow258(code,U32.is_lt(code,2729))
def propertiesBelow260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow257(code,U32.is_lt(code,2703))
    case False{}: propertiesBelow259(code,U32.is_lt(code,2707))
def propertiesBelow261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow256(code,U32.is_lt(code,2692))
    case False{}: propertiesBelow260(code,U32.is_lt(code,2706))
def propertiesBelow262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow262(code,U32.is_lt(code,2737))
    case False{}: propertiesBelow263(code,U32.is_lt(code,2740))
def propertiesBelow265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow266(code,U32.is_lt(code,2750))
def propertiesBelow268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow265(code,U32.is_lt(code,2746))
    case False{}: propertiesBelow267(code,U32.is_lt(code,2749))
def propertiesBelow269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow264(code,U32.is_lt(code,2738))
    case False{}: propertiesBelow268(code,U32.is_lt(code,2748))
def propertiesBelow270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow261(code,U32.is_lt(code,2702))
    case False{}: propertiesBelow269(code,U32.is_lt(code,2741))
def propertiesBelow271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow253(code,U32.is_lt(code,2642))
    case False{}: propertiesBelow270(code,U32.is_lt(code,2730))
def propertiesBelow272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow237(code,U32.is_lt(code,2561))
    case False{}: propertiesBelow271(code,U32.is_lt(code,2678))
def propertiesBelow273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow204(code,U32.is_lt(code,2250))
    case False{}: propertiesBelow272(code,U32.is_lt(code,2621))
def propertiesBelow274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow136(code,U32.is_lt(code,1162))
    case False{}: propertiesBelow273(code,U32.is_lt(code,2507))
def propertiesBelow275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow275(code,U32.is_lt(code,2759))
    case False{}: propertiesBelow276(code,U32.is_lt(code,2763))
def propertiesBelow278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow278(code,U32.is_lt(code,2768))
    case False{}: propertiesBelow279(code,U32.is_lt(code,2784))
def propertiesBelow281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow277(code,U32.is_lt(code,2762))
    case False{}: propertiesBelow280(code,U32.is_lt(code,2769))
def propertiesBelow282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow282(code,U32.is_lt(code,2788))
    case False{}: propertiesBelow283(code,U32.is_lt(code,2800))
def propertiesBelow285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow286(code,U32.is_lt(code,2820))
def propertiesBelow288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow285(code,U32.is_lt(code,2810))
    case False{}: propertiesBelow287(code,U32.is_lt(code,2817))
def propertiesBelow289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow284(code,U32.is_lt(code,2790))
    case False{}: propertiesBelow288(code,U32.is_lt(code,2816))
def propertiesBelow290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow281(code,U32.is_lt(code,2766))
    case False{}: propertiesBelow289(code,U32.is_lt(code,2809))
def propertiesBelow291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow291(code,U32.is_lt(code,2829))
    case False{}: propertiesBelow292(code,U32.is_lt(code,2833))
def propertiesBelow294(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow295(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow296(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow294(code,U32.is_lt(code,2857))
    case False{}: propertiesBelow295(code,U32.is_lt(code,2865))
def propertiesBelow297(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow293(code,U32.is_lt(code,2831))
    case False{}: propertiesBelow296(code,U32.is_lt(code,2858))
def propertiesBelow298(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow299(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow300(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow298(code,U32.is_lt(code,2868))
    case False{}: propertiesBelow299(code,U32.is_lt(code,2874))
def propertiesBelow301(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow302(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow303(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow302(code,U32.is_lt(code,2887))
def propertiesBelow304(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow301(code,U32.is_lt(code,2877))
    case False{}: propertiesBelow303(code,U32.is_lt(code,2885))
def propertiesBelow305(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow300(code,U32.is_lt(code,2869))
    case False{}: propertiesBelow304(code,U32.is_lt(code,2878))
def propertiesBelow306(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow297(code,U32.is_lt(code,2835))
    case False{}: propertiesBelow305(code,U32.is_lt(code,2876))
def propertiesBelow307(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow290(code,U32.is_lt(code,2786))
    case False{}: propertiesBelow306(code,U32.is_lt(code,2866))
def propertiesBelow308(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow309(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow310(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow308(code,U32.is_lt(code,2891))
    case False{}: propertiesBelow309(code,U32.is_lt(code,2901))
def propertiesBelow311(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow312(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow313(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow311(code,U32.is_lt(code,2908))
    case False{}: propertiesBelow312(code,U32.is_lt(code,2911))
def propertiesBelow314(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow310(code,U32.is_lt(code,2894))
    case False{}: propertiesBelow313(code,U32.is_lt(code,2910))
def propertiesBelow315(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow316(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow317(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow315(code,U32.is_lt(code,2916))
    case False{}: propertiesBelow316(code,U32.is_lt(code,2928))
def propertiesBelow318(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow319(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow320(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow319(code,U32.is_lt(code,2948))
def propertiesBelow321(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow318(code,U32.is_lt(code,2930))
    case False{}: propertiesBelow320(code,U32.is_lt(code,2947))
def propertiesBelow322(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow317(code,U32.is_lt(code,2918))
    case False{}: propertiesBelow321(code,U32.is_lt(code,2946))
def propertiesBelow323(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow314(code,U32.is_lt(code,2904))
    case False{}: propertiesBelow322(code,U32.is_lt(code,2929))
def propertiesBelow324(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow325(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow326(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow324(code,U32.is_lt(code,2955))
    case False{}: propertiesBelow325(code,U32.is_lt(code,2961))
def propertiesBelow327(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow328(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow329(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow328(code,U32.is_lt(code,2972))
def propertiesBelow330(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow327(code,U32.is_lt(code,2966))
    case False{}: propertiesBelow329(code,U32.is_lt(code,2971))
def propertiesBelow331(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow326(code,U32.is_lt(code,2958))
    case False{}: propertiesBelow330(code,U32.is_lt(code,2969))
def propertiesBelow332(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow333(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow334(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow332(code,U32.is_lt(code,2974))
    case False{}: propertiesBelow333(code,U32.is_lt(code,2979))
def propertiesBelow335(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow336(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow337(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow336(code,U32.is_lt(code,3002))
def propertiesBelow338(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow335(code,U32.is_lt(code,2984))
    case False{}: propertiesBelow337(code,U32.is_lt(code,2990))
def propertiesBelow339(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow334(code,U32.is_lt(code,2976))
    case False{}: propertiesBelow338(code,U32.is_lt(code,2987))
def propertiesBelow340(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow331(code,U32.is_lt(code,2962))
    case False{}: propertiesBelow339(code,U32.is_lt(code,2981))
def propertiesBelow341(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow323(code,U32.is_lt(code,2914))
    case False{}: propertiesBelow340(code,U32.is_lt(code,2973))
def propertiesBelow342(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow307(code,U32.is_lt(code,2821))
    case False{}: propertiesBelow341(code,U32.is_lt(code,2949))
def propertiesBelow343(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow344(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow345(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow343(code,U32.is_lt(code,3011))
    case False{}: propertiesBelow344(code,U32.is_lt(code,3017))
def propertiesBelow346(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow347(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow348(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow346(code,U32.is_lt(code,3022))
    case False{}: propertiesBelow347(code,U32.is_lt(code,3025))
def propertiesBelow349(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow345(code,U32.is_lt(code,3014))
    case False{}: propertiesBelow348(code,U32.is_lt(code,3024))
def propertiesBelow350(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow351(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow352(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow350(code,U32.is_lt(code,3032))
    case False{}: propertiesBelow351(code,U32.is_lt(code,3056))
def propertiesBelow353(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow354(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow355(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow354(code,U32.is_lt(code,3089))
def propertiesBelow356(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow353(code,U32.is_lt(code,3077))
    case False{}: propertiesBelow355(code,U32.is_lt(code,3086))
def propertiesBelow357(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow352(code,U32.is_lt(code,3046))
    case False{}: propertiesBelow356(code,U32.is_lt(code,3085))
def propertiesBelow358(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow349(code,U32.is_lt(code,3018))
    case False{}: propertiesBelow357(code,U32.is_lt(code,3072))
def propertiesBelow359(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow360(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow361(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow359(code,U32.is_lt(code,3113))
    case False{}: propertiesBelow360(code,U32.is_lt(code,3130))
def propertiesBelow362(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow363(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow364(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow362(code,U32.is_lt(code,3133))
    case False{}: propertiesBelow363(code,U32.is_lt(code,3141))
def propertiesBelow365(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow361(code,U32.is_lt(code,3114))
    case False{}: propertiesBelow364(code,U32.is_lt(code,3134))
def propertiesBelow366(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow367(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow368(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow366(code,U32.is_lt(code,3145))
    case False{}: propertiesBelow367(code,U32.is_lt(code,3150))
def propertiesBelow369(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow370(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow371(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow370(code,U32.is_lt(code,3164))
def propertiesBelow372(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow369(code,U32.is_lt(code,3159))
    case False{}: propertiesBelow371(code,U32.is_lt(code,3163))
def propertiesBelow373(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow368(code,U32.is_lt(code,3146))
    case False{}: propertiesBelow372(code,U32.is_lt(code,3160))
def propertiesBelow374(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow365(code,U32.is_lt(code,3132))
    case False{}: propertiesBelow373(code,U32.is_lt(code,3157))
def propertiesBelow375(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow358(code,U32.is_lt(code,3031))
    case False{}: propertiesBelow374(code,U32.is_lt(code,3142))
def propertiesBelow376(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow377(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow378(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow376(code,U32.is_lt(code,3168))
    case False{}: propertiesBelow377(code,U32.is_lt(code,3172))
def propertiesBelow379(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow380(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow381(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow379(code,U32.is_lt(code,3184))
    case False{}: propertiesBelow380(code,U32.is_lt(code,3201))
def propertiesBelow382(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow378(code,U32.is_lt(code,3170))
    case False{}: propertiesBelow381(code,U32.is_lt(code,3200))
def propertiesBelow383(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow384(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow385(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow383(code,U32.is_lt(code,3205))
    case False{}: propertiesBelow384(code,U32.is_lt(code,3214))
def propertiesBelow386(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow387(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow388(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow387(code,U32.is_lt(code,3252))
def propertiesBelow389(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow386(code,U32.is_lt(code,3218))
    case False{}: propertiesBelow388(code,U32.is_lt(code,3242))
def propertiesBelow390(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow385(code,U32.is_lt(code,3213))
    case False{}: propertiesBelow389(code,U32.is_lt(code,3241))
def propertiesBelow391(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow382(code,U32.is_lt(code,3174))
    case False{}: propertiesBelow390(code,U32.is_lt(code,3217))
def propertiesBelow392(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow393(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow394(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow392(code,U32.is_lt(code,3258))
    case False{}: propertiesBelow393(code,U32.is_lt(code,3261))
def propertiesBelow395(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow396(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow397(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow396(code,U32.is_lt(code,3274))
def propertiesBelow398(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow395(code,U32.is_lt(code,3269))
    case False{}: propertiesBelow397(code,U32.is_lt(code,3273))
def propertiesBelow399(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow394(code,U32.is_lt(code,3260))
    case False{}: propertiesBelow398(code,U32.is_lt(code,3270))
def propertiesBelow400(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow401(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow402(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow400(code,U32.is_lt(code,3285))
    case False{}: propertiesBelow401(code,U32.is_lt(code,3292))
def propertiesBelow403(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow404(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow405(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow404(code,U32.is_lt(code,3302))
def propertiesBelow406(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow403(code,U32.is_lt(code,3296))
    case False{}: propertiesBelow405(code,U32.is_lt(code,3300))
def propertiesBelow407(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow402(code,U32.is_lt(code,3287))
    case False{}: propertiesBelow406(code,U32.is_lt(code,3298))
def propertiesBelow408(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow399(code,U32.is_lt(code,3262))
    case False{}: propertiesBelow407(code,U32.is_lt(code,3295))
def propertiesBelow409(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow391(code,U32.is_lt(code,3204))
    case False{}: propertiesBelow408(code,U32.is_lt(code,3278))
def propertiesBelow410(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow375(code,U32.is_lt(code,3090))
    case False{}: propertiesBelow409(code,U32.is_lt(code,3253))
def propertiesBelow411(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow342(code,U32.is_lt(code,2889))
    case False{}: propertiesBelow410(code,U32.is_lt(code,3166))
def propertiesBelow412(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow413(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow414(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow412(code,U32.is_lt(code,3313))
    case False{}: propertiesBelow413(code,U32.is_lt(code,3316))
def propertiesBelow415(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow416(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow417(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow415(code,U32.is_lt(code,3332))
    case False{}: propertiesBelow416(code,U32.is_lt(code,3342))
def propertiesBelow418(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow414(code,U32.is_lt(code,3315))
    case False{}: propertiesBelow417(code,U32.is_lt(code,3341))
def propertiesBelow419(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow420(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow421(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow419(code,U32.is_lt(code,3346))
    case False{}: propertiesBelow420(code,U32.is_lt(code,3389))
def propertiesBelow422(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow423(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow424(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow423(code,U32.is_lt(code,3402))
def propertiesBelow425(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow422(code,U32.is_lt(code,3397))
    case False{}: propertiesBelow424(code,U32.is_lt(code,3401))
def propertiesBelow426(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow421(code,U32.is_lt(code,3387))
    case False{}: propertiesBelow425(code,U32.is_lt(code,3398))
def propertiesBelow427(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow418(code,U32.is_lt(code,3328))
    case False{}: propertiesBelow426(code,U32.is_lt(code,3390))
def propertiesBelow428(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow429(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow430(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow428(code,U32.is_lt(code,3407))
    case False{}: propertiesBelow429(code,U32.is_lt(code,3415))
def propertiesBelow431(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow432(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow433(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow431(code,U32.is_lt(code,3423))
    case False{}: propertiesBelow432(code,U32.is_lt(code,3428))
def propertiesBelow434(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow430(code,U32.is_lt(code,3412))
    case False{}: propertiesBelow433(code,U32.is_lt(code,3426))
def propertiesBelow435(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow436(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow437(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow435(code,U32.is_lt(code,3440))
    case False{}: propertiesBelow436(code,U32.is_lt(code,3456))
def propertiesBelow438(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow439(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow440(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow439(code,U32.is_lt(code,3482))
def propertiesBelow441(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow438(code,U32.is_lt(code,3460))
    case False{}: propertiesBelow440(code,U32.is_lt(code,3479))
def propertiesBelow442(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow437(code,U32.is_lt(code,3450))
    case False{}: propertiesBelow441(code,U32.is_lt(code,3461))
def propertiesBelow443(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow434(code,U32.is_lt(code,3416))
    case False{}: propertiesBelow442(code,U32.is_lt(code,3457))
def propertiesBelow444(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow427(code,U32.is_lt(code,3345))
    case False{}: propertiesBelow443(code,U32.is_lt(code,3430))
def propertiesBelow445(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow446(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow447(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow445(code,U32.is_lt(code,3507))
    case False{}: propertiesBelow446(code,U32.is_lt(code,3517))
def propertiesBelow448(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow449(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow450(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow448(code,U32.is_lt(code,3520))
    case False{}: propertiesBelow449(code,U32.is_lt(code,3530))
def propertiesBelow451(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow447(code,U32.is_lt(code,3516))
    case False{}: propertiesBelow450(code,U32.is_lt(code,3527))
def propertiesBelow452(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow453(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow454(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow452(code,U32.is_lt(code,3535))
    case False{}: propertiesBelow453(code,U32.is_lt(code,3542))
def propertiesBelow455(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow456(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow457(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow456(code,U32.is_lt(code,3568))
def propertiesBelow458(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow455(code,U32.is_lt(code,3544))
    case False{}: propertiesBelow457(code,U32.is_lt(code,3558))
def propertiesBelow459(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow454(code,U32.is_lt(code,3541))
    case False{}: propertiesBelow458(code,U32.is_lt(code,3552))
def propertiesBelow460(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow451(code,U32.is_lt(code,3518))
    case False{}: propertiesBelow459(code,U32.is_lt(code,3543))
def propertiesBelow461(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow462(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow463(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow461(code,U32.is_lt(code,3572))
    case False{}: propertiesBelow462(code,U32.is_lt(code,3634))
def propertiesBelow464(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow465(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow466(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow465(code,U32.is_lt(code,3664))
def propertiesBelow467(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow464(code,U32.is_lt(code,3643))
    case False{}: propertiesBelow466(code,U32.is_lt(code,3663))
def propertiesBelow468(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow463(code,U32.is_lt(code,3633))
    case False{}: propertiesBelow467(code,U32.is_lt(code,3655))
def propertiesBelow469(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow470(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow471(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow469(code,U32.is_lt(code,3761))
    case False{}: propertiesBelow470(code,U32.is_lt(code,3764))
def propertiesBelow472(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow473(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow474(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow473(code,U32.is_lt(code,3802))
def propertiesBelow475(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow472(code,U32.is_lt(code,3784))
    case False{}: propertiesBelow474(code,U32.is_lt(code,3792))
def propertiesBelow476(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow471(code,U32.is_lt(code,3762))
    case False{}: propertiesBelow475(code,U32.is_lt(code,3791))
def propertiesBelow477(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow468(code,U32.is_lt(code,3636))
    case False{}: propertiesBelow476(code,U32.is_lt(code,3773))
def propertiesBelow478(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow460(code,U32.is_lt(code,3531))
    case False{}: propertiesBelow477(code,U32.is_lt(code,3674))
def propertiesBelow479(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow444(code,U32.is_lt(code,3406))
    case False{}: propertiesBelow478(code,U32.is_lt(code,3570))
def propertiesBelow480(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow481(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow482(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow480(code,U32.is_lt(code,3841))
    case False{}: propertiesBelow481(code,U32.is_lt(code,3866))
def propertiesBelow483(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow484(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow485(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow483(code,U32.is_lt(code,3882))
    case False{}: propertiesBelow484(code,U32.is_lt(code,3894))
def propertiesBelow486(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow482(code,U32.is_lt(code,3864))
    case False{}: propertiesBelow485(code,U32.is_lt(code,3893))
def propertiesBelow487(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow488(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow489(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow487(code,U32.is_lt(code,3896))
    case False{}: propertiesBelow488(code,U32.is_lt(code,3898))
def propertiesBelow490(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow491(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow492(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow491(code,U32.is_lt(code,3949))
def propertiesBelow493(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow490(code,U32.is_lt(code,3904))
    case False{}: propertiesBelow492(code,U32.is_lt(code,3913))
def propertiesBelow494(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow489(code,U32.is_lt(code,3897))
    case False{}: propertiesBelow493(code,U32.is_lt(code,3912))
def propertiesBelow495(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow486(code,U32.is_lt(code,3872))
    case False{}: propertiesBelow494(code,U32.is_lt(code,3902))
def propertiesBelow496(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow497(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow498(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow496(code,U32.is_lt(code,3973))
    case False{}: propertiesBelow497(code,U32.is_lt(code,3976))
def propertiesBelow499(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow500(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow501(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow499(code,U32.is_lt(code,3992))
    case False{}: propertiesBelow500(code,U32.is_lt(code,4029))
def propertiesBelow502(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow498(code,U32.is_lt(code,3974))
    case False{}: propertiesBelow501(code,U32.is_lt(code,3993))
def propertiesBelow503(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow504(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow505(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow503(code,U32.is_lt(code,4039))
    case False{}: propertiesBelow504(code,U32.is_lt(code,4159))
def propertiesBelow506(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow507(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow508(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow507(code,U32.is_lt(code,4190))
def propertiesBelow509(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow506(code,U32.is_lt(code,4170))
    case False{}: propertiesBelow508(code,U32.is_lt(code,4186))
def propertiesBelow510(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow505(code,U32.is_lt(code,4139))
    case False{}: propertiesBelow509(code,U32.is_lt(code,4182))
def propertiesBelow511(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow502(code,U32.is_lt(code,3981))
    case False{}: propertiesBelow510(code,U32.is_lt(code,4160))
def propertiesBelow512(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow495(code,U32.is_lt(code,3895))
    case False{}: propertiesBelow511(code,U32.is_lt(code,4038))
def propertiesBelow513(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow514(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow515(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow513(code,U32.is_lt(code,4194))
    case False{}: propertiesBelow514(code,U32.is_lt(code,4199))
def propertiesBelow516(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow517(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow518(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow516(code,U32.is_lt(code,4209))
    case False{}: propertiesBelow517(code,U32.is_lt(code,4226))
def propertiesBelow519(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow515(code,U32.is_lt(code,4197))
    case False{}: propertiesBelow518(code,U32.is_lt(code,4213))
def propertiesBelow520(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow521(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 4
def propertiesBelow522(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow520(code,U32.is_lt(code,4239))
    case False{}: propertiesBelow521(code,U32.is_lt(code,4250))
def propertiesBelow523(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow524(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow525(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow524(code,U32.is_lt(code,4296))
def propertiesBelow526(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow523(code,U32.is_lt(code,4256))
    case False{}: propertiesBelow525(code,U32.is_lt(code,4295))
def propertiesBelow527(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow522(code,U32.is_lt(code,4240))
    case False{}: propertiesBelow526(code,U32.is_lt(code,4294))
def propertiesBelow528(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow519(code,U32.is_lt(code,4206))
    case False{}: propertiesBelow527(code,U32.is_lt(code,4254))
def propertiesBelow529(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow530(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow531(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow529(code,U32.is_lt(code,4302))
    case False{}: propertiesBelow530(code,U32.is_lt(code,4347))
def propertiesBelow532(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow533(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow534(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow533(code,U32.is_lt(code,4688))
def propertiesBelow535(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow532(code,U32.is_lt(code,4681))
    case False{}: propertiesBelow534(code,U32.is_lt(code,4686))
def propertiesBelow536(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow531(code,U32.is_lt(code,4304))
    case False{}: propertiesBelow535(code,U32.is_lt(code,4682))
def propertiesBelow537(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow538(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow539(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow537(code,U32.is_lt(code,4696))
    case False{}: propertiesBelow538(code,U32.is_lt(code,4698))
def propertiesBelow540(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow541(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow542(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow541(code,U32.is_lt(code,4750))
def propertiesBelow543(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow540(code,U32.is_lt(code,4704))
    case False{}: propertiesBelow542(code,U32.is_lt(code,4746))
def propertiesBelow544(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow539(code,U32.is_lt(code,4697))
    case False{}: propertiesBelow543(code,U32.is_lt(code,4745))
def propertiesBelow545(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow536(code,U32.is_lt(code,4348))
    case False{}: propertiesBelow544(code,U32.is_lt(code,4702))
def propertiesBelow546(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow528(code,U32.is_lt(code,4238))
    case False{}: propertiesBelow545(code,U32.is_lt(code,4695))
def propertiesBelow547(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow512(code,U32.is_lt(code,3953))
    case False{}: propertiesBelow546(code,U32.is_lt(code,4301))
def propertiesBelow548(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow479(code,U32.is_lt(code,3506))
    case False{}: propertiesBelow547(code,U32.is_lt(code,4193))
def propertiesBelow549(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow411(code,U32.is_lt(code,3006))
    case False{}: propertiesBelow548(code,U32.is_lt(code,3840))
def propertiesBelow550(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow274(code,U32.is_lt(code,1969))
    case False{}: propertiesBelow549(code,U32.is_lt(code,3312))
def propertiesBelow551(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow552(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow553(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow551(code,U32.is_lt(code,4785))
    case False{}: propertiesBelow552(code,U32.is_lt(code,4790))
def propertiesBelow554(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow555(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow556(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow554(code,U32.is_lt(code,4799))
    case False{}: propertiesBelow555(code,U32.is_lt(code,4801))
def propertiesBelow557(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow553(code,U32.is_lt(code,4786))
    case False{}: propertiesBelow556(code,U32.is_lt(code,4800))
def propertiesBelow558(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow559(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow560(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow558(code,U32.is_lt(code,4806))
    case False{}: propertiesBelow559(code,U32.is_lt(code,4823))
def propertiesBelow561(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow562(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow563(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow562(code,U32.is_lt(code,4888))
def propertiesBelow564(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow561(code,U32.is_lt(code,4881))
    case False{}: propertiesBelow563(code,U32.is_lt(code,4886))
def propertiesBelow565(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow560(code,U32.is_lt(code,4808))
    case False{}: propertiesBelow564(code,U32.is_lt(code,4882))
def propertiesBelow566(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow557(code,U32.is_lt(code,4792))
    case False{}: propertiesBelow565(code,U32.is_lt(code,4824))
def propertiesBelow567(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow568(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow569(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow567(code,U32.is_lt(code,4957))
    case False{}: propertiesBelow568(code,U32.is_lt(code,4992))
def propertiesBelow570(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow571(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow572(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow570(code,U32.is_lt(code,5024))
    case False{}: propertiesBelow571(code,U32.is_lt(code,5112))
def propertiesBelow573(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow569(code,U32.is_lt(code,4960))
    case False{}: propertiesBelow572(code,U32.is_lt(code,5110))
def propertiesBelow574(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow575(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow576(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow574(code,U32.is_lt(code,5121))
    case False{}: propertiesBelow575(code,U32.is_lt(code,5743))
def propertiesBelow577(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 7
    case False{}: 8
def propertiesBelow578(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow579(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow578(code,U32.is_lt(code,5867))
def propertiesBelow580(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow577(code,U32.is_lt(code,5761))
    case False{}: propertiesBelow579(code,U32.is_lt(code,5792))
def propertiesBelow581(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow576(code,U32.is_lt(code,5741))
    case False{}: propertiesBelow580(code,U32.is_lt(code,5787))
def propertiesBelow582(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow573(code,U32.is_lt(code,5008))
    case False{}: propertiesBelow581(code,U32.is_lt(code,5760))
def propertiesBelow583(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow566(code,U32.is_lt(code,4802))
    case False{}: propertiesBelow582(code,U32.is_lt(code,5118))
def propertiesBelow584(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow585(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow586(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow584(code,U32.is_lt(code,5881))
    case False{}: propertiesBelow585(code,U32.is_lt(code,5906))
def propertiesBelow587(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow588(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow589(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow587(code,U32.is_lt(code,5919))
    case False{}: propertiesBelow588(code,U32.is_lt(code,5941))
def propertiesBelow590(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow586(code,U32.is_lt(code,5888))
    case False{}: propertiesBelow589(code,U32.is_lt(code,5938))
def propertiesBelow591(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow592(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow593(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow591(code,U32.is_lt(code,5970))
    case False{}: propertiesBelow592(code,U32.is_lt(code,5984))
def propertiesBelow594(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow595(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow596(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow595(code,U32.is_lt(code,6004))
def propertiesBelow597(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow594(code,U32.is_lt(code,5998))
    case False{}: propertiesBelow596(code,U32.is_lt(code,6002))
def propertiesBelow598(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow593(code,U32.is_lt(code,5972))
    case False{}: propertiesBelow597(code,U32.is_lt(code,6001))
def propertiesBelow599(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow590(code,U32.is_lt(code,5910))
    case False{}: propertiesBelow598(code,U32.is_lt(code,5997))
def propertiesBelow600(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow601(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow602(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow600(code,U32.is_lt(code,6100))
    case False{}: propertiesBelow601(code,U32.is_lt(code,6110))
def propertiesBelow603(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow604(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 4
def propertiesBelow605(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow604(code,U32.is_lt(code,6159))
def propertiesBelow606(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow603(code,U32.is_lt(code,6122))
    case False{}: propertiesBelow605(code,U32.is_lt(code,6158))
def propertiesBelow607(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow602(code,U32.is_lt(code,6109))
    case False{}: propertiesBelow606(code,U32.is_lt(code,6155))
def propertiesBelow608(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow609(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow610(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow608(code,U32.is_lt(code,6170))
    case False{}: propertiesBelow609(code,U32.is_lt(code,6265))
def propertiesBelow611(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow612(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow613(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow612(code,U32.is_lt(code,6314))
def propertiesBelow614(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow611(code,U32.is_lt(code,6277))
    case False{}: propertiesBelow613(code,U32.is_lt(code,6313))
def propertiesBelow615(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow610(code,U32.is_lt(code,6176))
    case False{}: propertiesBelow614(code,U32.is_lt(code,6279))
def propertiesBelow616(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow607(code,U32.is_lt(code,6112))
    case False{}: propertiesBelow615(code,U32.is_lt(code,6272))
def propertiesBelow617(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow599(code,U32.is_lt(code,5952))
    case False{}: propertiesBelow616(code,U32.is_lt(code,6160))
def propertiesBelow618(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow583(code,U32.is_lt(code,4955))
    case False{}: propertiesBelow617(code,U32.is_lt(code,6068))
def propertiesBelow619(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow620(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow621(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow619(code,U32.is_lt(code,6320))
    case False{}: propertiesBelow620(code,U32.is_lt(code,6400))
def propertiesBelow622(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow623(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow624(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow622(code,U32.is_lt(code,6432))
    case False{}: propertiesBelow623(code,U32.is_lt(code,6448))
def propertiesBelow625(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow621(code,U32.is_lt(code,6390))
    case False{}: propertiesBelow624(code,U32.is_lt(code,6444))
def propertiesBelow626(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow627(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow628(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow626(code,U32.is_lt(code,6470))
    case False{}: propertiesBelow627(code,U32.is_lt(code,6608))
def propertiesBelow629(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow630(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow631(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow630(code,U32.is_lt(code,6741))
def propertiesBelow632(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow629(code,U32.is_lt(code,6656))
    case False{}: propertiesBelow631(code,U32.is_lt(code,6684))
def propertiesBelow633(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow628(code,U32.is_lt(code,6480))
    case False{}: propertiesBelow632(code,U32.is_lt(code,6679))
def propertiesBelow634(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow625(code,U32.is_lt(code,6431))
    case False{}: propertiesBelow633(code,U32.is_lt(code,6619))
def propertiesBelow635(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow636(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow637(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow635(code,U32.is_lt(code,6752))
    case False{}: propertiesBelow636(code,U32.is_lt(code,6783))
def propertiesBelow638(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow639(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow640(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow638(code,U32.is_lt(code,6794))
    case False{}: propertiesBelow639(code,U32.is_lt(code,6810))
def propertiesBelow641(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow637(code,U32.is_lt(code,6781))
    case False{}: propertiesBelow640(code,U32.is_lt(code,6800))
def propertiesBelow642(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow643(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow644(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow642(code,U32.is_lt(code,6878))
    case False{}: propertiesBelow643(code,U32.is_lt(code,6892))
def propertiesBelow645(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow646(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow647(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow646(code,U32.is_lt(code,6989))
def propertiesBelow648(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow645(code,U32.is_lt(code,6917))
    case False{}: propertiesBelow647(code,U32.is_lt(code,6981))
def propertiesBelow649(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow644(code,U32.is_lt(code,6880))
    case False{}: propertiesBelow648(code,U32.is_lt(code,6964))
def propertiesBelow650(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow641(code,U32.is_lt(code,6784))
    case False{}: propertiesBelow649(code,U32.is_lt(code,6912))
def propertiesBelow651(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow634(code,U32.is_lt(code,6460))
    case False{}: propertiesBelow650(code,U32.is_lt(code,6832))
def propertiesBelow652(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow653(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow654(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow652(code,U32.is_lt(code,7002))
    case False{}: propertiesBelow653(code,U32.is_lt(code,7028))
def propertiesBelow655(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow656(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow657(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow655(code,U32.is_lt(code,7043))
    case False{}: propertiesBelow656(code,U32.is_lt(code,7086))
def propertiesBelow658(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow654(code,U32.is_lt(code,7019))
    case False{}: propertiesBelow657(code,U32.is_lt(code,7073))
def propertiesBelow659(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 8
def propertiesBelow660(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow661(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow659(code,U32.is_lt(code,7098))
    case False{}: propertiesBelow660(code,U32.is_lt(code,7156))
def propertiesBelow662(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow663(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow664(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow663(code,U32.is_lt(code,7242))
def propertiesBelow665(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow662(code,U32.is_lt(code,7204))
    case False{}: propertiesBelow664(code,U32.is_lt(code,7232))
def propertiesBelow666(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow661(code,U32.is_lt(code,7142))
    case False{}: propertiesBelow665(code,U32.is_lt(code,7224))
def propertiesBelow667(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow658(code,U32.is_lt(code,7040))
    case False{}: propertiesBelow666(code,U32.is_lt(code,7168))
def propertiesBelow668(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow669(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow670(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow668(code,U32.is_lt(code,7248))
    case False{}: propertiesBelow669(code,U32.is_lt(code,7294))
def propertiesBelow671(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow672(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow673(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow672(code,U32.is_lt(code,7357))
def propertiesBelow674(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow671(code,U32.is_lt(code,7307))
    case False{}: propertiesBelow673(code,U32.is_lt(code,7355))
def propertiesBelow675(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow670(code,U32.is_lt(code,7258))
    case False{}: propertiesBelow674(code,U32.is_lt(code,7312))
def propertiesBelow676(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow677(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow678(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow676(code,U32.is_lt(code,7376))
    case False{}: propertiesBelow677(code,U32.is_lt(code,7380))
def propertiesBelow679(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow680(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow681(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow680(code,U32.is_lt(code,7413))
def propertiesBelow682(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow679(code,U32.is_lt(code,7405))
    case False{}: propertiesBelow681(code,U32.is_lt(code,7412))
def propertiesBelow683(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow678(code,U32.is_lt(code,7379))
    case False{}: propertiesBelow682(code,U32.is_lt(code,7406))
def propertiesBelow684(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow675(code,U32.is_lt(code,7296))
    case False{}: propertiesBelow683(code,U32.is_lt(code,7401))
def propertiesBelow685(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow667(code,U32.is_lt(code,7088))
    case False{}: propertiesBelow684(code,U32.is_lt(code,7360))
def propertiesBelow686(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow651(code,U32.is_lt(code,6751))
    case False{}: propertiesBelow685(code,U32.is_lt(code,7245))
def propertiesBelow687(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow618(code,U32.is_lt(code,5870))
    case False{}: propertiesBelow686(code,U32.is_lt(code,6992))
def propertiesBelow688(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow689(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow690(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow688(code,U32.is_lt(code,7418))
    case False{}: propertiesBelow689(code,U32.is_lt(code,7424))
def propertiesBelow691(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow692(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow693(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow691(code,U32.is_lt(code,7680))
    case False{}: propertiesBelow692(code,U32.is_lt(code,7960))
def propertiesBelow694(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow690(code,U32.is_lt(code,7419))
    case False{}: propertiesBelow693(code,U32.is_lt(code,7958))
def propertiesBelow695(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow696(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow697(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow695(code,U32.is_lt(code,7968))
    case False{}: propertiesBelow696(code,U32.is_lt(code,8008))
def propertiesBelow698(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow699(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow700(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow699(code,U32.is_lt(code,8026))
def propertiesBelow701(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow698(code,U32.is_lt(code,8016))
    case False{}: propertiesBelow700(code,U32.is_lt(code,8025))
def propertiesBelow702(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow697(code,U32.is_lt(code,8006))
    case False{}: propertiesBelow701(code,U32.is_lt(code,8024))
def propertiesBelow703(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow694(code,U32.is_lt(code,7616))
    case False{}: propertiesBelow702(code,U32.is_lt(code,8014))
def propertiesBelow704(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow705(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow706(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow704(code,U32.is_lt(code,8028))
    case False{}: propertiesBelow705(code,U32.is_lt(code,8030))
def propertiesBelow707(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow708(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow709(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow707(code,U32.is_lt(code,8062))
    case False{}: propertiesBelow708(code,U32.is_lt(code,8117))
def propertiesBelow710(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow706(code,U32.is_lt(code,8029))
    case False{}: propertiesBelow709(code,U32.is_lt(code,8064))
def propertiesBelow711(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow712(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow713(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow711(code,U32.is_lt(code,8125))
    case False{}: propertiesBelow712(code,U32.is_lt(code,8127))
def propertiesBelow714(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow715(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow716(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow715(code,U32.is_lt(code,8144))
def propertiesBelow717(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow714(code,U32.is_lt(code,8133))
    case False{}: propertiesBelow716(code,U32.is_lt(code,8141))
def propertiesBelow718(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow713(code,U32.is_lt(code,8126))
    case False{}: propertiesBelow717(code,U32.is_lt(code,8134))
def propertiesBelow719(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow710(code,U32.is_lt(code,8031))
    case False{}: propertiesBelow718(code,U32.is_lt(code,8130))
def propertiesBelow720(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow703(code,U32.is_lt(code,7966))
    case False{}: propertiesBelow719(code,U32.is_lt(code,8118))
def propertiesBelow721(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow722(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow723(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow721(code,U32.is_lt(code,8150))
    case False{}: propertiesBelow722(code,U32.is_lt(code,8160))
def propertiesBelow724(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow725(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow726(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow724(code,U32.is_lt(code,8178))
    case False{}: propertiesBelow725(code,U32.is_lt(code,8182))
def propertiesBelow727(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow723(code,U32.is_lt(code,8156))
    case False{}: propertiesBelow726(code,U32.is_lt(code,8181))
def propertiesBelow728(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7
def propertiesBelow729(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7
def propertiesBelow730(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow728(code,U32.is_lt(code,8192))
    case False{}: propertiesBelow729(code,U32.is_lt(code,8200))
def propertiesBelow731(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow732(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow733(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 6
    case False{}: propertiesBelow732(code,U32.is_lt(code,8208))
def propertiesBelow734(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow731(code,U32.is_lt(code,8204))
    case False{}: propertiesBelow733(code,U32.is_lt(code,8206))
def propertiesBelow735(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow730(code,U32.is_lt(code,8199))
    case False{}: propertiesBelow734(code,U32.is_lt(code,8205))
def propertiesBelow736(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow727(code,U32.is_lt(code,8173))
    case False{}: propertiesBelow735(code,U32.is_lt(code,8203))
def propertiesBelow737(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 15
    case False{}: 0
def propertiesBelow738(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 15
    case False{}: 0
def propertiesBelow739(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow737(code,U32.is_lt(code,8218))
    case False{}: propertiesBelow738(code,U32.is_lt(code,8229))
def propertiesBelow740(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 13
    case False{}: 3
def propertiesBelow741(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 12
    case False{}: 0
def propertiesBelow742(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: propertiesBelow741(code,U32.is_lt(code,8240))
def propertiesBelow743(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow740(code,U32.is_lt(code,8232))
    case False{}: propertiesBelow742(code,U32.is_lt(code,8239))
def propertiesBelow744(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow739(code,U32.is_lt(code,8228))
    case False{}: propertiesBelow743(code,U32.is_lt(code,8234))
def propertiesBelow745(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow746(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 12
    case False{}: 0
def propertiesBelow747(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow745(code,U32.is_lt(code,8253))
    case False{}: propertiesBelow746(code,U32.is_lt(code,8257))
def propertiesBelow748(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 14
    case False{}: 0
def propertiesBelow749(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 12
def propertiesBelow750(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow749(code,U32.is_lt(code,8276))
def propertiesBelow751(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow748(code,U32.is_lt(code,8261))
    case False{}: propertiesBelow750(code,U32.is_lt(code,8266))
def propertiesBelow752(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow747(code,U32.is_lt(code,8255))
    case False{}: propertiesBelow751(code,U32.is_lt(code,8265))
def propertiesBelow753(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow744(code,U32.is_lt(code,8231))
    case False{}: propertiesBelow752(code,U32.is_lt(code,8260))
def propertiesBelow754(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow736(code,U32.is_lt(code,8189))
    case False{}: propertiesBelow753(code,U32.is_lt(code,8252))
def propertiesBelow755(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow720(code,U32.is_lt(code,8027))
    case False{}: propertiesBelow754(code,U32.is_lt(code,8216))
def propertiesBelow756(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7
def propertiesBelow757(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow758(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow756(code,U32.is_lt(code,8287))
    case False{}: propertiesBelow757(code,U32.is_lt(code,8293))
def propertiesBelow759(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow760(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow761(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow759(code,U32.is_lt(code,8304))
    case False{}: propertiesBelow760(code,U32.is_lt(code,8306))
def propertiesBelow762(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow758(code,U32.is_lt(code,8288))
    case False{}: propertiesBelow761(code,U32.is_lt(code,8305))
def propertiesBelow763(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow764(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow765(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow763(code,U32.is_lt(code,8320))
    case False{}: propertiesBelow764(code,U32.is_lt(code,8349))
def propertiesBelow766(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow767(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow768(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow767(code,U32.is_lt(code,8455))
def propertiesBelow769(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow766(code,U32.is_lt(code,8433))
    case False{}: propertiesBelow768(code,U32.is_lt(code,8451))
def propertiesBelow770(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow765(code,U32.is_lt(code,8336))
    case False{}: propertiesBelow769(code,U32.is_lt(code,8450))
def propertiesBelow771(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow762(code,U32.is_lt(code,8294))
    case False{}: propertiesBelow770(code,U32.is_lt(code,8400))
def propertiesBelow772(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow773(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow774(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow772(code,U32.is_lt(code,8458))
    case False{}: propertiesBelow773(code,U32.is_lt(code,8469))
def propertiesBelow775(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow776(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow777(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow775(code,U32.is_lt(code,8473))
    case False{}: propertiesBelow776(code,U32.is_lt(code,8482))
def propertiesBelow778(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow774(code,U32.is_lt(code,8468))
    case False{}: propertiesBelow777(code,U32.is_lt(code,8478))
def propertiesBelow779(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow780(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow781(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow779(code,U32.is_lt(code,8484))
    case False{}: propertiesBelow780(code,U32.is_lt(code,8486))
def propertiesBelow782(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow783(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow784(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow783(code,U32.is_lt(code,8494))
def propertiesBelow785(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow782(code,U32.is_lt(code,8488))
    case False{}: propertiesBelow784(code,U32.is_lt(code,8490))
def propertiesBelow786(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow781(code,U32.is_lt(code,8485))
    case False{}: propertiesBelow785(code,U32.is_lt(code,8489))
def propertiesBelow787(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow778(code,U32.is_lt(code,8470))
    case False{}: propertiesBelow786(code,U32.is_lt(code,8487))
def propertiesBelow788(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow771(code,U32.is_lt(code,8319))
    case False{}: propertiesBelow787(code,U32.is_lt(code,8483))
def propertiesBelow789(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 40
def propertiesBelow790(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow791(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow789(code,U32.is_lt(code,8505))
    case False{}: propertiesBelow790(code,U32.is_lt(code,8508))
def propertiesBelow792(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow793(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow794(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow792(code,U32.is_lt(code,8517))
    case False{}: propertiesBelow793(code,U32.is_lt(code,8526))
def propertiesBelow795(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow791(code,U32.is_lt(code,8506))
    case False{}: propertiesBelow794(code,U32.is_lt(code,8522))
def propertiesBelow796(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow797(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow798(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow796(code,U32.is_lt(code,8544))
    case False{}: propertiesBelow797(code,U32.is_lt(code,8596))
def propertiesBelow799(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow800(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow801(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow800(code,U32.is_lt(code,8988))
def propertiesBelow802(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow799(code,U32.is_lt(code,8617))
    case False{}: propertiesBelow801(code,U32.is_lt(code,8986))
def propertiesBelow803(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow798(code,U32.is_lt(code,8585))
    case False{}: propertiesBelow802(code,U32.is_lt(code,8619))
def propertiesBelow804(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow795(code,U32.is_lt(code,8512))
    case False{}: propertiesBelow803(code,U32.is_lt(code,8602))
def propertiesBelow805(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow806(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow807(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow805(code,U32.is_lt(code,9001))
    case False{}: propertiesBelow806(code,U32.is_lt(code,9168))
def propertiesBelow808(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow809(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow810(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow809(code,U32.is_lt(code,9398))
def propertiesBelow811(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow808(code,U32.is_lt(code,9204))
    case False{}: propertiesBelow810(code,U32.is_lt(code,9211))
def propertiesBelow812(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow807(code,U32.is_lt(code,9167))
    case False{}: propertiesBelow811(code,U32.is_lt(code,9208))
def propertiesBelow813(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 40
    case False{}: 8
def propertiesBelow814(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow815(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow813(code,U32.is_lt(code,9411))
    case False{}: propertiesBelow814(code,U32.is_lt(code,9642))
def propertiesBelow816(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow817(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow818(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow817(code,U32.is_lt(code,9665))
def propertiesBelow819(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow816(code,U32.is_lt(code,9654))
    case False{}: propertiesBelow818(code,U32.is_lt(code,9664))
def propertiesBelow820(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow815(code,U32.is_lt(code,9450))
    case False{}: propertiesBelow819(code,U32.is_lt(code,9655))
def propertiesBelow821(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow812(code,U32.is_lt(code,9193))
    case False{}: propertiesBelow820(code,U32.is_lt(code,9644))
def propertiesBelow822(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow804(code,U32.is_lt(code,8527))
    case False{}: propertiesBelow821(code,U32.is_lt(code,9410))
def propertiesBelow823(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow788(code,U32.is_lt(code,8456))
    case False{}: propertiesBelow822(code,U32.is_lt(code,9000))
def propertiesBelow824(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow755(code,U32.is_lt(code,8148))
    case False{}: propertiesBelow823(code,U32.is_lt(code,8495))
def propertiesBelow825(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow687(code,U32.is_lt(code,6315))
    case False{}: propertiesBelow824(code,U32.is_lt(code,8277))
def propertiesBelow826(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow827(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow828(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow826(code,U32.is_lt(code,9727))
    case False{}: propertiesBelow827(code,U32.is_lt(code,9733))
def propertiesBelow829(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow830(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow831(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow829(code,U32.is_lt(code,9743))
    case False{}: propertiesBelow830(code,U32.is_lt(code,9746))
def propertiesBelow832(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow828(code,U32.is_lt(code,9728))
    case False{}: propertiesBelow831(code,U32.is_lt(code,9745))
def propertiesBelow833(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow834(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow835(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow833(code,U32.is_lt(code,9750))
    case False{}: propertiesBelow834(code,U32.is_lt(code,9753))
def propertiesBelow836(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow837(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow838(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow837(code,U32.is_lt(code,9762))
def propertiesBelow839(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow836(code,U32.is_lt(code,9758))
    case False{}: propertiesBelow838(code,U32.is_lt(code,9761))
def propertiesBelow840(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow835(code,U32.is_lt(code,9752))
    case False{}: propertiesBelow839(code,U32.is_lt(code,9760))
def propertiesBelow841(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow832(code,U32.is_lt(code,9742))
    case False{}: propertiesBelow840(code,U32.is_lt(code,9757))
def propertiesBelow842(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow843(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow844(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow842(code,U32.is_lt(code,9766))
    case False{}: propertiesBelow843(code,U32.is_lt(code,9770))
def propertiesBelow845(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow846(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow847(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow845(code,U32.is_lt(code,9774))
    case False{}: propertiesBelow846(code,U32.is_lt(code,9784))
def propertiesBelow848(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow844(code,U32.is_lt(code,9767))
    case False{}: propertiesBelow847(code,U32.is_lt(code,9776))
def propertiesBelow849(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow850(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow851(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow849(code,U32.is_lt(code,9792))
    case False{}: propertiesBelow850(code,U32.is_lt(code,9794))
def propertiesBelow852(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow853(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow854(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow853(code,U32.is_lt(code,9825))
def propertiesBelow855(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow852(code,U32.is_lt(code,9800))
    case False{}: propertiesBelow854(code,U32.is_lt(code,9823))
def propertiesBelow856(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow851(code,U32.is_lt(code,9793))
    case False{}: propertiesBelow855(code,U32.is_lt(code,9812))
def propertiesBelow857(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow848(code,U32.is_lt(code,9771))
    case False{}: propertiesBelow856(code,U32.is_lt(code,9795))
def propertiesBelow858(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow841(code,U32.is_lt(code,9748))
    case False{}: propertiesBelow857(code,U32.is_lt(code,9787))
def propertiesBelow859(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow860(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow861(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow859(code,U32.is_lt(code,9828))
    case False{}: propertiesBelow860(code,U32.is_lt(code,9831))
def propertiesBelow862(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow863(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow864(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow862(code,U32.is_lt(code,9833))
    case False{}: propertiesBelow863(code,U32.is_lt(code,9852))
def propertiesBelow865(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow861(code,U32.is_lt(code,9829))
    case False{}: propertiesBelow864(code,U32.is_lt(code,9851))
def propertiesBelow866(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow867(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow868(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow866(code,U32.is_lt(code,9856))
    case False{}: propertiesBelow867(code,U32.is_lt(code,9880))
def propertiesBelow869(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow870(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow871(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow870(code,U32.is_lt(code,9888))
def propertiesBelow872(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow869(code,U32.is_lt(code,9882))
    case False{}: propertiesBelow871(code,U32.is_lt(code,9885))
def propertiesBelow873(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow868(code,U32.is_lt(code,9874))
    case False{}: propertiesBelow872(code,U32.is_lt(code,9883))
def propertiesBelow874(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow865(code,U32.is_lt(code,9832))
    case False{}: propertiesBelow873(code,U32.is_lt(code,9881))
def propertiesBelow875(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow876(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow877(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow875(code,U32.is_lt(code,9895))
    case False{}: propertiesBelow876(code,U32.is_lt(code,9898))
def propertiesBelow878(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow879(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow880(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow879(code,U32.is_lt(code,9919))
def propertiesBelow881(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow878(code,U32.is_lt(code,9904))
    case False{}: propertiesBelow880(code,U32.is_lt(code,9917))
def propertiesBelow882(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow877(code,U32.is_lt(code,9896))
    case False{}: propertiesBelow881(code,U32.is_lt(code,9906))
def propertiesBelow883(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow884(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow885(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow883(code,U32.is_lt(code,9926))
    case False{}: propertiesBelow884(code,U32.is_lt(code,9929))
def propertiesBelow886(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow887(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow888(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow887(code,U32.is_lt(code,9939))
def propertiesBelow889(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow886(code,U32.is_lt(code,9936))
    case False{}: propertiesBelow888(code,U32.is_lt(code,9938))
def propertiesBelow890(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow885(code,U32.is_lt(code,9928))
    case False{}: propertiesBelow889(code,U32.is_lt(code,9937))
def propertiesBelow891(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow882(code,U32.is_lt(code,9900))
    case False{}: propertiesBelow890(code,U32.is_lt(code,9934))
def propertiesBelow892(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow874(code,U32.is_lt(code,9854))
    case False{}: propertiesBelow891(code,U32.is_lt(code,9924))
def propertiesBelow893(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow858(code,U32.is_lt(code,9764))
    case False{}: propertiesBelow892(code,U32.is_lt(code,9890))
def propertiesBelow894(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow895(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow896(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow894(code,U32.is_lt(code,9961))
    case False{}: propertiesBelow895(code,U32.is_lt(code,9968))
def propertiesBelow897(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow898(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow899(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow897(code,U32.is_lt(code,9975))
    case False{}: propertiesBelow898(code,U32.is_lt(code,9981))
def propertiesBelow900(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow896(code,U32.is_lt(code,9963))
    case False{}: propertiesBelow899(code,U32.is_lt(code,9979))
def propertiesBelow901(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow902(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow903(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow901(code,U32.is_lt(code,9986))
    case False{}: propertiesBelow902(code,U32.is_lt(code,9989))
def propertiesBelow904(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow905(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow906(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow905(code,U32.is_lt(code,10000))
def propertiesBelow907(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow904(code,U32.is_lt(code,9992))
    case False{}: propertiesBelow906(code,U32.is_lt(code,9999))
def propertiesBelow908(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow903(code,U32.is_lt(code,9987))
    case False{}: propertiesBelow907(code,U32.is_lt(code,9998))
def propertiesBelow909(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow900(code,U32.is_lt(code,9974))
    case False{}: propertiesBelow908(code,U32.is_lt(code,9990))
def propertiesBelow910(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow911(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow912(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow910(code,U32.is_lt(code,10003))
    case False{}: propertiesBelow911(code,U32.is_lt(code,10005))
def propertiesBelow913(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow914(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow915(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow913(code,U32.is_lt(code,10007))
    case False{}: propertiesBelow914(code,U32.is_lt(code,10014))
def propertiesBelow916(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow912(code,U32.is_lt(code,10004))
    case False{}: propertiesBelow915(code,U32.is_lt(code,10013))
def propertiesBelow917(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow918(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow919(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow917(code,U32.is_lt(code,10018))
    case False{}: propertiesBelow918(code,U32.is_lt(code,10025))
def propertiesBelow920(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow921(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow922(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow921(code,U32.is_lt(code,10055))
def propertiesBelow923(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow920(code,U32.is_lt(code,10037))
    case False{}: propertiesBelow922(code,U32.is_lt(code,10053))
def propertiesBelow924(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow919(code,U32.is_lt(code,10024))
    case False{}: propertiesBelow923(code,U32.is_lt(code,10052))
def propertiesBelow925(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow916(code,U32.is_lt(code,10006))
    case False{}: propertiesBelow924(code,U32.is_lt(code,10035))
def propertiesBelow926(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow909(code,U32.is_lt(code,9982))
    case False{}: propertiesBelow925(code,U32.is_lt(code,10017))
def propertiesBelow927(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow928(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow929(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow927(code,U32.is_lt(code,10060))
    case False{}: propertiesBelow928(code,U32.is_lt(code,10062))
def propertiesBelow930(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow931(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow932(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow930(code,U32.is_lt(code,10067))
    case False{}: propertiesBelow931(code,U32.is_lt(code,10071))
def propertiesBelow933(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow929(code,U32.is_lt(code,10061))
    case False{}: propertiesBelow932(code,U32.is_lt(code,10070))
def propertiesBelow934(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow935(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow936(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow934(code,U32.is_lt(code,10083))
    case False{}: propertiesBelow935(code,U32.is_lt(code,10133))
def propertiesBelow937(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow938(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow939(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow938(code,U32.is_lt(code,10161))
def propertiesBelow940(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow937(code,U32.is_lt(code,10145))
    case False{}: propertiesBelow939(code,U32.is_lt(code,10160))
def propertiesBelow941(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow936(code,U32.is_lt(code,10085))
    case False{}: propertiesBelow940(code,U32.is_lt(code,10146))
def propertiesBelow942(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow933(code,U32.is_lt(code,10063))
    case False{}: propertiesBelow941(code,U32.is_lt(code,10136))
def propertiesBelow943(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow944(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow945(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow943(code,U32.is_lt(code,10176))
    case False{}: propertiesBelow944(code,U32.is_lt(code,10550))
def propertiesBelow946(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow947(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow948(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow947(code,U32.is_lt(code,11088))
def propertiesBelow949(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow946(code,U32.is_lt(code,11016))
    case False{}: propertiesBelow948(code,U32.is_lt(code,11037))
def propertiesBelow950(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow945(code,U32.is_lt(code,10548))
    case False{}: propertiesBelow949(code,U32.is_lt(code,11035))
def propertiesBelow951(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow952(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow953(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow951(code,U32.is_lt(code,11093))
    case False{}: propertiesBelow952(code,U32.is_lt(code,11264))
def propertiesBelow954(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow955(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow956(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow955(code,U32.is_lt(code,11508))
def propertiesBelow957(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow954(code,U32.is_lt(code,11499))
    case False{}: propertiesBelow956(code,U32.is_lt(code,11506))
def propertiesBelow958(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow953(code,U32.is_lt(code,11094))
    case False{}: propertiesBelow957(code,U32.is_lt(code,11503))
def propertiesBelow959(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow950(code,U32.is_lt(code,11013))
    case False{}: propertiesBelow958(code,U32.is_lt(code,11493))
def propertiesBelow960(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow942(code,U32.is_lt(code,10072))
    case False{}: propertiesBelow959(code,U32.is_lt(code,11089))
def propertiesBelow961(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow926(code,U32.is_lt(code,10002))
    case False{}: propertiesBelow960(code,U32.is_lt(code,10175))
def propertiesBelow962(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow893(code,U32.is_lt(code,9827))
    case False{}: propertiesBelow961(code,U32.is_lt(code,10056))
def propertiesBelow963(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow964(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow965(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow963(code,U32.is_lt(code,11558))
    case False{}: propertiesBelow964(code,U32.is_lt(code,11560))
def propertiesBelow966(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow967(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow968(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow966(code,U32.is_lt(code,11566))
    case False{}: propertiesBelow967(code,U32.is_lt(code,11624))
def propertiesBelow969(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow965(code,U32.is_lt(code,11559))
    case False{}: propertiesBelow968(code,U32.is_lt(code,11568))
def propertiesBelow970(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow971(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow972(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow970(code,U32.is_lt(code,11632))
    case False{}: propertiesBelow971(code,U32.is_lt(code,11648))
def propertiesBelow973(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow974(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow975(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow974(code,U32.is_lt(code,11695))
def propertiesBelow976(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow973(code,U32.is_lt(code,11680))
    case False{}: propertiesBelow975(code,U32.is_lt(code,11688))
def propertiesBelow977(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow972(code,U32.is_lt(code,11647))
    case False{}: propertiesBelow976(code,U32.is_lt(code,11687))
def propertiesBelow978(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow969(code,U32.is_lt(code,11565))
    case False{}: propertiesBelow977(code,U32.is_lt(code,11671))
def propertiesBelow979(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow980(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow981(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow979(code,U32.is_lt(code,11703))
    case False{}: propertiesBelow980(code,U32.is_lt(code,11711))
def propertiesBelow982(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow983(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow984(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow982(code,U32.is_lt(code,11719))
    case False{}: propertiesBelow983(code,U32.is_lt(code,11727))
def propertiesBelow985(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow981(code,U32.is_lt(code,11704))
    case False{}: propertiesBelow984(code,U32.is_lt(code,11720))
def propertiesBelow986(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow987(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow988(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow986(code,U32.is_lt(code,11735))
    case False{}: propertiesBelow987(code,U32.is_lt(code,11743))
def propertiesBelow989(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow990(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 7
def propertiesBelow991(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow990(code,U32.is_lt(code,12288))
def propertiesBelow992(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow989(code,U32.is_lt(code,11776))
    case False{}: propertiesBelow991(code,U32.is_lt(code,11824))
def propertiesBelow993(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow988(code,U32.is_lt(code,11736))
    case False{}: propertiesBelow992(code,U32.is_lt(code,11823))
def propertiesBelow994(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow985(code,U32.is_lt(code,11712))
    case False{}: propertiesBelow993(code,U32.is_lt(code,11744))
def propertiesBelow995(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow978(code,U32.is_lt(code,11631))
    case False{}: propertiesBelow994(code,U32.is_lt(code,11728))
def propertiesBelow996(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow997(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow998(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow996(code,U32.is_lt(code,12293))
    case False{}: propertiesBelow997(code,U32.is_lt(code,12330))
def propertiesBelow999(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 11
def propertiesBelow1000(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1001(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow999(code,U32.is_lt(code,12337))
    case False{}: propertiesBelow1000(code,U32.is_lt(code,12347))
def propertiesBelow1002(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow998(code,U32.is_lt(code,12294))
    case False{}: propertiesBelow1001(code,U32.is_lt(code,12342))
def propertiesBelow1003(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow1004(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 11
def propertiesBelow1005(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1003(code,U32.is_lt(code,12350))
    case False{}: propertiesBelow1004(code,U32.is_lt(code,12443))
def propertiesBelow1006(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1007(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 11
    case False{}: 0
def propertiesBelow1008(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1007(code,U32.is_lt(code,12544))
def propertiesBelow1009(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1006(code,U32.is_lt(code,12448))
    case False{}: propertiesBelow1008(code,U32.is_lt(code,12540))
def propertiesBelow1010(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1005(code,U32.is_lt(code,12441))
    case False{}: propertiesBelow1009(code,U32.is_lt(code,12539))
def propertiesBelow1011(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1002(code,U32.is_lt(code,12336))
    case False{}: propertiesBelow1010(code,U32.is_lt(code,12445))
def propertiesBelow1012(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1013(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1014(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1012(code,U32.is_lt(code,12592))
    case False{}: propertiesBelow1013(code,U32.is_lt(code,12687))
def propertiesBelow1015(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1016(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow1017(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 11
    case False{}: propertiesBelow1016(code,U32.is_lt(code,12951))
def propertiesBelow1018(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1015(code,U32.is_lt(code,12736))
    case False{}: propertiesBelow1017(code,U32.is_lt(code,12800))
def propertiesBelow1019(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1014(code,U32.is_lt(code,12593))
    case False{}: propertiesBelow1018(code,U32.is_lt(code,12784))
def propertiesBelow1020(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow1021(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1022(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1020(code,U32.is_lt(code,12953))
    case False{}: propertiesBelow1021(code,U32.is_lt(code,13008))
def propertiesBelow1023(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1024(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1025(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1024(code,U32.is_lt(code,42125))
def propertiesBelow1026(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1023(code,U32.is_lt(code,13056))
    case False{}: propertiesBelow1025(code,U32.is_lt(code,40960))
def propertiesBelow1027(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1022(code,U32.is_lt(code,12954))
    case False{}: propertiesBelow1026(code,U32.is_lt(code,13144))
def propertiesBelow1028(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1019(code,U32.is_lt(code,12704))
    case False{}: propertiesBelow1027(code,U32.is_lt(code,13055))
def propertiesBelow1029(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1011(code,U32.is_lt(code,12349))
    case False{}: propertiesBelow1028(code,U32.is_lt(code,12952))
def propertiesBelow1030(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow995(code,U32.is_lt(code,11696))
    case False{}: propertiesBelow1029(code,U32.is_lt(code,12549))
def propertiesBelow1031(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1032(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1033(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1031(code,U32.is_lt(code,42238))
    case False{}: propertiesBelow1032(code,U32.is_lt(code,42509))
def propertiesBelow1034(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow1035(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1036(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1034(code,U32.is_lt(code,42528))
    case False{}: propertiesBelow1035(code,U32.is_lt(code,42540))
def propertiesBelow1037(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1033(code,U32.is_lt(code,42240))
    case False{}: propertiesBelow1036(code,U32.is_lt(code,42538))
def propertiesBelow1038(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1039(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1040(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1038(code,U32.is_lt(code,42607))
    case False{}: propertiesBelow1039(code,U32.is_lt(code,42612))
def propertiesBelow1041(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1042(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1043(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1042(code,U32.is_lt(code,42736))
def propertiesBelow1044(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1041(code,U32.is_lt(code,42623))
    case False{}: propertiesBelow1043(code,U32.is_lt(code,42656))
def propertiesBelow1045(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1040(code,U32.is_lt(code,42611))
    case False{}: propertiesBelow1044(code,U32.is_lt(code,42654))
def propertiesBelow1046(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1037(code,U32.is_lt(code,42512))
    case False{}: propertiesBelow1045(code,U32.is_lt(code,42622))
def propertiesBelow1047(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1048(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1049(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1047(code,U32.is_lt(code,42760))
    case False{}: propertiesBelow1048(code,U32.is_lt(code,42993))
def propertiesBelow1050(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1051(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1052(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1051(code,U32.is_lt(code,43019))
def propertiesBelow1053(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1050(code,U32.is_lt(code,43011))
    case False{}: propertiesBelow1052(code,U32.is_lt(code,43015))
def propertiesBelow1054(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1049(code,U32.is_lt(code,42973))
    case False{}: propertiesBelow1053(code,U32.is_lt(code,43014))
def propertiesBelow1055(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1056(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1057(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1055(code,U32.is_lt(code,43043))
    case False{}: propertiesBelow1056(code,U32.is_lt(code,43052))
def propertiesBelow1058(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1059(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1060(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1059(code,U32.is_lt(code,43138))
def propertiesBelow1061(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1058(code,U32.is_lt(code,43072))
    case False{}: propertiesBelow1060(code,U32.is_lt(code,43136))
def propertiesBelow1062(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1057(code,U32.is_lt(code,43048))
    case False{}: propertiesBelow1061(code,U32.is_lt(code,43124))
def propertiesBelow1063(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1054(code,U32.is_lt(code,43010))
    case False{}: propertiesBelow1062(code,U32.is_lt(code,43053))
def propertiesBelow1064(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1046(code,U32.is_lt(code,42560))
    case False{}: propertiesBelow1063(code,U32.is_lt(code,43020))
def propertiesBelow1065(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1066(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1067(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1065(code,U32.is_lt(code,43206))
    case False{}: propertiesBelow1066(code,U32.is_lt(code,43226))
def propertiesBelow1068(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1069(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1070(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1068(code,U32.is_lt(code,43250))
    case False{}: propertiesBelow1069(code,U32.is_lt(code,43259))
def propertiesBelow1071(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1067(code,U32.is_lt(code,43216))
    case False{}: propertiesBelow1070(code,U32.is_lt(code,43256))
def propertiesBelow1072(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1073(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 10
def propertiesBelow1074(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1072(code,U32.is_lt(code,43261))
    case False{}: propertiesBelow1073(code,U32.is_lt(code,43264))
def propertiesBelow1075(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1076(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1077(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1076(code,U32.is_lt(code,43335))
def propertiesBelow1078(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1075(code,U32.is_lt(code,43302))
    case False{}: propertiesBelow1077(code,U32.is_lt(code,43312))
def propertiesBelow1079(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1074(code,U32.is_lt(code,43263))
    case False{}: propertiesBelow1078(code,U32.is_lt(code,43310))
def propertiesBelow1080(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1071(code,U32.is_lt(code,43232))
    case False{}: propertiesBelow1079(code,U32.is_lt(code,43274))
def propertiesBelow1081(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1082(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1083(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1081(code,U32.is_lt(code,43360))
    case False{}: propertiesBelow1082(code,U32.is_lt(code,43392))
def propertiesBelow1084(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1085(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow1086(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1085(code,U32.is_lt(code,43472))
def propertiesBelow1087(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1084(code,U32.is_lt(code,43443))
    case False{}: propertiesBelow1086(code,U32.is_lt(code,43471))
def propertiesBelow1088(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1083(code,U32.is_lt(code,43389))
    case False{}: propertiesBelow1087(code,U32.is_lt(code,43457))
def propertiesBelow1089(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1090(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1091(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1089(code,U32.is_lt(code,43493))
    case False{}: propertiesBelow1090(code,U32.is_lt(code,43504))
def propertiesBelow1092(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1093(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1094(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1093(code,U32.is_lt(code,43584))
def propertiesBelow1095(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1092(code,U32.is_lt(code,43520))
    case False{}: propertiesBelow1094(code,U32.is_lt(code,43575))
def propertiesBelow1096(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1091(code,U32.is_lt(code,43494))
    case False{}: propertiesBelow1095(code,U32.is_lt(code,43561))
def propertiesBelow1097(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1088(code,U32.is_lt(code,43396))
    case False{}: propertiesBelow1096(code,U32.is_lt(code,43514))
def propertiesBelow1098(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1080(code,U32.is_lt(code,43260))
    case False{}: propertiesBelow1097(code,U32.is_lt(code,43482))
def propertiesBelow1099(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1064(code,U32.is_lt(code,42738))
    case False{}: propertiesBelow1098(code,U32.is_lt(code,43348))
def propertiesBelow1100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1030(code,U32.is_lt(code,12289))
    case False{}: propertiesBelow1099(code,U32.is_lt(code,43188))
def propertiesBelow1101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow962(code,U32.is_lt(code,9941))
    case False{}: propertiesBelow1100(code,U32.is_lt(code,42192))
def propertiesBelow1102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow825(code,U32.is_lt(code,7415))
    case False{}: propertiesBelow1101(code,U32.is_lt(code,11520))
def propertiesBelow1103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow550(code,U32.is_lt(code,2758))
    case False{}: propertiesBelow1102(code,U32.is_lt(code,9723))
def propertiesBelow1104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1104(code,U32.is_lt(code,43588))
    case False{}: propertiesBelow1105(code,U32.is_lt(code,43598))
def propertiesBelow1107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1107(code,U32.is_lt(code,43610))
    case False{}: propertiesBelow1108(code,U32.is_lt(code,43646))
def propertiesBelow1110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1106(code,U32.is_lt(code,43596))
    case False{}: propertiesBelow1109(code,U32.is_lt(code,43643))
def propertiesBelow1111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1111(code,U32.is_lt(code,43697))
    case False{}: propertiesBelow1112(code,U32.is_lt(code,43701))
def propertiesBelow1114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1115(code,U32.is_lt(code,43713))
def propertiesBelow1117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1114(code,U32.is_lt(code,43705))
    case False{}: propertiesBelow1116(code,U32.is_lt(code,43712))
def propertiesBelow1118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1113(code,U32.is_lt(code,43698))
    case False{}: propertiesBelow1117(code,U32.is_lt(code,43710))
def propertiesBelow1119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1110(code,U32.is_lt(code,43600))
    case False{}: propertiesBelow1118(code,U32.is_lt(code,43703))
def propertiesBelow1120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1120(code,U32.is_lt(code,43744))
    case False{}: propertiesBelow1121(code,U32.is_lt(code,43760))
def propertiesBelow1123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1123(code,U32.is_lt(code,43765))
    case False{}: propertiesBelow1124(code,U32.is_lt(code,43777))
def propertiesBelow1126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1122(code,U32.is_lt(code,43755))
    case False{}: propertiesBelow1125(code,U32.is_lt(code,43767))
def propertiesBelow1127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1127(code,U32.is_lt(code,43785))
    case False{}: propertiesBelow1128(code,U32.is_lt(code,43793))
def propertiesBelow1130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1131(code,U32.is_lt(code,43823))
def propertiesBelow1133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1130(code,U32.is_lt(code,43808))
    case False{}: propertiesBelow1132(code,U32.is_lt(code,43816))
def propertiesBelow1134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1129(code,U32.is_lt(code,43791))
    case False{}: propertiesBelow1133(code,U32.is_lt(code,43815))
def propertiesBelow1135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1126(code,U32.is_lt(code,43762))
    case False{}: propertiesBelow1134(code,U32.is_lt(code,43799))
def propertiesBelow1136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1119(code,U32.is_lt(code,43696))
    case False{}: propertiesBelow1135(code,U32.is_lt(code,43783))
def propertiesBelow1137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1137(code,U32.is_lt(code,43882))
    case False{}: propertiesBelow1138(code,U32.is_lt(code,44003))
def propertiesBelow1140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1140(code,U32.is_lt(code,44012))
    case False{}: propertiesBelow1141(code,U32.is_lt(code,44016))
def propertiesBelow1143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1139(code,U32.is_lt(code,43888))
    case False{}: propertiesBelow1142(code,U32.is_lt(code,44014))
def propertiesBelow1144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1144(code,U32.is_lt(code,44032))
    case False{}: propertiesBelow1145(code,U32.is_lt(code,55216))
def propertiesBelow1147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1148(code,U32.is_lt(code,64263))
def propertiesBelow1150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1147(code,U32.is_lt(code,55243))
    case False{}: propertiesBelow1149(code,U32.is_lt(code,64256))
def propertiesBelow1151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1146(code,U32.is_lt(code,55204))
    case False{}: propertiesBelow1150(code,U32.is_lt(code,55292))
def propertiesBelow1152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1143(code,U32.is_lt(code,44011))
    case False{}: propertiesBelow1151(code,U32.is_lt(code,55239))
def propertiesBelow1153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 9
    case False{}: 4
def propertiesBelow1155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1153(code,U32.is_lt(code,64280))
    case False{}: propertiesBelow1154(code,U32.is_lt(code,64286))
def propertiesBelow1156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 9
    case False{}: 0
def propertiesBelow1157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow1158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 9
    case False{}: propertiesBelow1157(code,U32.is_lt(code,64312))
def propertiesBelow1159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1156(code,U32.is_lt(code,64297))
    case False{}: propertiesBelow1158(code,U32.is_lt(code,64311))
def propertiesBelow1160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1155(code,U32.is_lt(code,64285))
    case False{}: propertiesBelow1159(code,U32.is_lt(code,64298))
def propertiesBelow1161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow1162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow1163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1161(code,U32.is_lt(code,64318))
    case False{}: propertiesBelow1162(code,U32.is_lt(code,64320))
def propertiesBelow1164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 9
def propertiesBelow1165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 9
    case False{}: 8
def propertiesBelow1166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1165(code,U32.is_lt(code,64336))
def propertiesBelow1167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1164(code,U32.is_lt(code,64323))
    case False{}: propertiesBelow1166(code,U32.is_lt(code,64326))
def propertiesBelow1168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1163(code,U32.is_lt(code,64319))
    case False{}: propertiesBelow1167(code,U32.is_lt(code,64325))
def propertiesBelow1169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1160(code,U32.is_lt(code,64287))
    case False{}: propertiesBelow1168(code,U32.is_lt(code,64322))
def propertiesBelow1170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1152(code,U32.is_lt(code,44026))
    case False{}: propertiesBelow1169(code,U32.is_lt(code,64317))
def propertiesBelow1171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1136(code,U32.is_lt(code,43714))
    case False{}: propertiesBelow1170(code,U32.is_lt(code,64275))
def propertiesBelow1172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1172(code,U32.is_lt(code,64467))
    case False{}: propertiesBelow1173(code,U32.is_lt(code,64848))
def propertiesBelow1175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1175(code,U32.is_lt(code,64914))
    case False{}: propertiesBelow1176(code,U32.is_lt(code,65008))
def propertiesBelow1178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1174(code,U32.is_lt(code,64830))
    case False{}: propertiesBelow1177(code,U32.is_lt(code,64968))
def propertiesBelow1179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 13
def propertiesBelow1181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1179(code,U32.is_lt(code,65024))
    case False{}: propertiesBelow1180(code,U32.is_lt(code,65043))
def propertiesBelow1182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 12
    case False{}: 0
def propertiesBelow1184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1183(code,U32.is_lt(code,65077))
def propertiesBelow1185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1182(code,U32.is_lt(code,65056))
    case False{}: propertiesBelow1184(code,U32.is_lt(code,65075))
def propertiesBelow1186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1181(code,U32.is_lt(code,65040))
    case False{}: propertiesBelow1185(code,U32.is_lt(code,65072))
def propertiesBelow1187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1178(code,U32.is_lt(code,64912))
    case False{}: propertiesBelow1186(code,U32.is_lt(code,65044))
def propertiesBelow1188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 12
    case False{}: 14
def propertiesBelow1189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 15
def propertiesBelow1190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1188(code,U32.is_lt(code,65104))
    case False{}: propertiesBelow1189(code,U32.is_lt(code,65106))
def propertiesBelow1191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 14
def propertiesBelow1192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 13
    case False{}: 0
def propertiesBelow1193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1191(code,U32.is_lt(code,65108))
    case False{}: propertiesBelow1192(code,U32.is_lt(code,65110))
def propertiesBelow1194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1190(code,U32.is_lt(code,65105))
    case False{}: propertiesBelow1193(code,U32.is_lt(code,65109))
def propertiesBelow1195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1195(code,U32.is_lt(code,65141))
    case False{}: propertiesBelow1196(code,U32.is_lt(code,65277))
def propertiesBelow1198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow1199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 14
def propertiesBelow1200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 15
    case False{}: propertiesBelow1199(code,U32.is_lt(code,65292))
def propertiesBelow1201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1198(code,U32.is_lt(code,65280))
    case False{}: propertiesBelow1200(code,U32.is_lt(code,65288))
def propertiesBelow1202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1197(code,U32.is_lt(code,65142))
    case False{}: propertiesBelow1201(code,U32.is_lt(code,65287))
def propertiesBelow1203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1194(code,U32.is_lt(code,65107))
    case False{}: propertiesBelow1202(code,U32.is_lt(code,65279))
def propertiesBelow1204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1187(code,U32.is_lt(code,65020))
    case False{}: propertiesBelow1203(code,U32.is_lt(code,65136))
def propertiesBelow1205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 15
def propertiesBelow1206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1205(code,U32.is_lt(code,65294))
    case False{}: propertiesBelow1206(code,U32.is_lt(code,65296))
def propertiesBelow1208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 13
    case False{}: 14
def propertiesBelow1209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1210(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1208(code,U32.is_lt(code,65307))
    case False{}: propertiesBelow1209(code,U32.is_lt(code,65313))
def propertiesBelow1211(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1207(code,U32.is_lt(code,65295))
    case False{}: propertiesBelow1210(code,U32.is_lt(code,65308))
def propertiesBelow1212(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 12
def propertiesBelow1213(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1214(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1212(code,U32.is_lt(code,65343))
    case False{}: propertiesBelow1213(code,U32.is_lt(code,65345))
def propertiesBelow1215(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1216(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1217(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1216(code,U32.is_lt(code,65471))
def propertiesBelow1218(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1215(code,U32.is_lt(code,65382))
    case False{}: propertiesBelow1217(code,U32.is_lt(code,65440))
def propertiesBelow1219(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1214(code,U32.is_lt(code,65344))
    case False{}: propertiesBelow1218(code,U32.is_lt(code,65438))
def propertiesBelow1220(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1211(code,U32.is_lt(code,65306))
    case False{}: propertiesBelow1219(code,U32.is_lt(code,65371))
def propertiesBelow1221(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1222(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1223(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1221(code,U32.is_lt(code,65480))
    case False{}: propertiesBelow1222(code,U32.is_lt(code,65488))
def propertiesBelow1224(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1225(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 5
def propertiesBelow1226(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1225(code,U32.is_lt(code,65529))
def propertiesBelow1227(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1224(code,U32.is_lt(code,65496))
    case False{}: propertiesBelow1226(code,U32.is_lt(code,65501))
def propertiesBelow1228(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1223(code,U32.is_lt(code,65482))
    case False{}: propertiesBelow1227(code,U32.is_lt(code,65498))
def propertiesBelow1229(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1230(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1231(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1229(code,U32.is_lt(code,65536))
    case False{}: propertiesBelow1230(code,U32.is_lt(code,65549))
def propertiesBelow1232(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1233(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1234(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1233(code,U32.is_lt(code,65598))
def propertiesBelow1235(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1232(code,U32.is_lt(code,65576))
    case False{}: propertiesBelow1234(code,U32.is_lt(code,65596))
def propertiesBelow1236(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1231(code,U32.is_lt(code,65548))
    case False{}: propertiesBelow1235(code,U32.is_lt(code,65595))
def propertiesBelow1237(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1228(code,U32.is_lt(code,65490))
    case False{}: propertiesBelow1236(code,U32.is_lt(code,65575))
def propertiesBelow1238(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1220(code,U32.is_lt(code,65339))
    case False{}: propertiesBelow1237(code,U32.is_lt(code,65532))
def propertiesBelow1239(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1204(code,U32.is_lt(code,65101))
    case False{}: propertiesBelow1238(code,U32.is_lt(code,65474))
def propertiesBelow1240(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1171(code,U32.is_lt(code,43824))
    case False{}: propertiesBelow1239(code,U32.is_lt(code,65293))
def propertiesBelow1241(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1242(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1243(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1241(code,U32.is_lt(code,65614))
    case False{}: propertiesBelow1242(code,U32.is_lt(code,65630))
def propertiesBelow1244(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1245(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1246(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1244(code,U32.is_lt(code,65787))
    case False{}: propertiesBelow1245(code,U32.is_lt(code,65909))
def propertiesBelow1247(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1243(code,U32.is_lt(code,65616))
    case False{}: propertiesBelow1246(code,U32.is_lt(code,65856))
def propertiesBelow1248(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1249(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1250(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1248(code,U32.is_lt(code,66046))
    case False{}: propertiesBelow1249(code,U32.is_lt(code,66205))
def propertiesBelow1251(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1252(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1253(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1252(code,U32.is_lt(code,66304))
def propertiesBelow1254(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1251(code,U32.is_lt(code,66257))
    case False{}: propertiesBelow1253(code,U32.is_lt(code,66273))
def propertiesBelow1255(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1250(code,U32.is_lt(code,66176))
    case False{}: propertiesBelow1254(code,U32.is_lt(code,66272))
def propertiesBelow1256(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1247(code,U32.is_lt(code,65664))
    case False{}: propertiesBelow1255(code,U32.is_lt(code,66208))
def propertiesBelow1257(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1258(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1259(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1257(code,U32.is_lt(code,66349))
    case False{}: propertiesBelow1258(code,U32.is_lt(code,66384))
def propertiesBelow1260(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1261(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1262(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1260(code,U32.is_lt(code,66427))
    case False{}: propertiesBelow1261(code,U32.is_lt(code,66462))
def propertiesBelow1263(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1259(code,U32.is_lt(code,66379))
    case False{}: propertiesBelow1262(code,U32.is_lt(code,66432))
def propertiesBelow1264(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1265(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1266(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1264(code,U32.is_lt(code,66500))
    case False{}: propertiesBelow1265(code,U32.is_lt(code,66512))
def propertiesBelow1267(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1268(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1269(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1268(code,U32.is_lt(code,66720))
def propertiesBelow1270(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1267(code,U32.is_lt(code,66518))
    case False{}: propertiesBelow1269(code,U32.is_lt(code,66718))
def propertiesBelow1271(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1266(code,U32.is_lt(code,66504))
    case False{}: propertiesBelow1270(code,U32.is_lt(code,66560))
def propertiesBelow1272(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1263(code,U32.is_lt(code,66422))
    case False{}: propertiesBelow1271(code,U32.is_lt(code,66513))
def propertiesBelow1273(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1256(code,U32.is_lt(code,66045))
    case False{}: propertiesBelow1272(code,U32.is_lt(code,66464))
def propertiesBelow1274(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1275(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1276(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1274(code,U32.is_lt(code,66736))
    case False{}: propertiesBelow1275(code,U32.is_lt(code,66776))
def propertiesBelow1277(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1278(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1279(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1277(code,U32.is_lt(code,66816))
    case False{}: propertiesBelow1278(code,U32.is_lt(code,66864))
def propertiesBelow1280(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1276(code,U32.is_lt(code,66772))
    case False{}: propertiesBelow1279(code,U32.is_lt(code,66856))
def propertiesBelow1281(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1282(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1283(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1281(code,U32.is_lt(code,66928))
    case False{}: propertiesBelow1282(code,U32.is_lt(code,66940))
def propertiesBelow1284(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1285(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1286(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1285(code,U32.is_lt(code,66966))
def propertiesBelow1287(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1284(code,U32.is_lt(code,66956))
    case False{}: propertiesBelow1286(code,U32.is_lt(code,66964))
def propertiesBelow1288(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1283(code,U32.is_lt(code,66939))
    case False{}: propertiesBelow1287(code,U32.is_lt(code,66963))
def propertiesBelow1289(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1280(code,U32.is_lt(code,66812))
    case False{}: propertiesBelow1288(code,U32.is_lt(code,66955))
def propertiesBelow1290(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1291(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1292(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1290(code,U32.is_lt(code,66978))
    case False{}: propertiesBelow1291(code,U32.is_lt(code,66994))
def propertiesBelow1293(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1294(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1295(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1294(code,U32.is_lt(code,67008))
def propertiesBelow1296(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1293(code,U32.is_lt(code,67002))
    case False{}: propertiesBelow1295(code,U32.is_lt(code,67005))
def propertiesBelow1297(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1292(code,U32.is_lt(code,66979))
    case False{}: propertiesBelow1296(code,U32.is_lt(code,67003))
def propertiesBelow1298(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1299(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1300(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1298(code,U32.is_lt(code,67072))
    case False{}: propertiesBelow1299(code,U32.is_lt(code,67392))
def propertiesBelow1301(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1302(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1303(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1302(code,U32.is_lt(code,67462))
def propertiesBelow1304(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1301(code,U32.is_lt(code,67424))
    case False{}: propertiesBelow1303(code,U32.is_lt(code,67456))
def propertiesBelow1305(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1300(code,U32.is_lt(code,67383))
    case False{}: propertiesBelow1304(code,U32.is_lt(code,67432))
def propertiesBelow1306(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1297(code,U32.is_lt(code,66995))
    case False{}: propertiesBelow1305(code,U32.is_lt(code,67414))
def propertiesBelow1307(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1289(code,U32.is_lt(code,66916))
    case False{}: propertiesBelow1306(code,U32.is_lt(code,67060))
def propertiesBelow1308(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1273(code,U32.is_lt(code,66336))
    case False{}: propertiesBelow1307(code,U32.is_lt(code,66967))
def propertiesBelow1309(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1310(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1311(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1309(code,U32.is_lt(code,67505))
    case False{}: propertiesBelow1310(code,U32.is_lt(code,67515))
def propertiesBelow1312(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1313(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1314(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1312(code,U32.is_lt(code,67590))
    case False{}: propertiesBelow1313(code,U32.is_lt(code,67593))
def propertiesBelow1315(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1311(code,U32.is_lt(code,67506))
    case False{}: propertiesBelow1314(code,U32.is_lt(code,67592))
def propertiesBelow1316(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1317(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1318(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1316(code,U32.is_lt(code,67638))
    case False{}: propertiesBelow1317(code,U32.is_lt(code,67641))
def propertiesBelow1319(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1320(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1321(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1320(code,U32.is_lt(code,67680))
def propertiesBelow1322(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1319(code,U32.is_lt(code,67645))
    case False{}: propertiesBelow1321(code,U32.is_lt(code,67670))
def propertiesBelow1323(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1318(code,U32.is_lt(code,67639))
    case False{}: propertiesBelow1322(code,U32.is_lt(code,67647))
def propertiesBelow1324(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1315(code,U32.is_lt(code,67584))
    case False{}: propertiesBelow1323(code,U32.is_lt(code,67644))
def propertiesBelow1325(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1326(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1327(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1325(code,U32.is_lt(code,67712))
    case False{}: propertiesBelow1326(code,U32.is_lt(code,67808))
def propertiesBelow1328(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1329(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1330(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1328(code,U32.is_lt(code,67828))
    case False{}: propertiesBelow1329(code,U32.is_lt(code,67840))
def propertiesBelow1331(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1327(code,U32.is_lt(code,67743))
    case False{}: propertiesBelow1330(code,U32.is_lt(code,67830))
def propertiesBelow1332(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1333(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1334(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1332(code,U32.is_lt(code,67872))
    case False{}: propertiesBelow1333(code,U32.is_lt(code,67904))
def propertiesBelow1335(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1336(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1337(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1336(code,U32.is_lt(code,68032))
def propertiesBelow1338(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1335(code,U32.is_lt(code,67968))
    case False{}: propertiesBelow1337(code,U32.is_lt(code,68030))
def propertiesBelow1339(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1334(code,U32.is_lt(code,67898))
    case False{}: propertiesBelow1338(code,U32.is_lt(code,68024))
def propertiesBelow1340(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1331(code,U32.is_lt(code,67827))
    case False{}: propertiesBelow1339(code,U32.is_lt(code,67930))
def propertiesBelow1341(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1324(code,U32.is_lt(code,67594))
    case False{}: propertiesBelow1340(code,U32.is_lt(code,67862))
def propertiesBelow1342(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1343(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1344(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1342(code,U32.is_lt(code,68097))
    case False{}: propertiesBelow1343(code,U32.is_lt(code,68101))
def propertiesBelow1345(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1346(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1347(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1345(code,U32.is_lt(code,68108))
    case False{}: propertiesBelow1346(code,U32.is_lt(code,68116))
def propertiesBelow1348(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1344(code,U32.is_lt(code,68100))
    case False{}: propertiesBelow1347(code,U32.is_lt(code,68112))
def propertiesBelow1349(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1350(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1351(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1349(code,U32.is_lt(code,68120))
    case False{}: propertiesBelow1350(code,U32.is_lt(code,68150))
def propertiesBelow1352(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1353(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1354(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1353(code,U32.is_lt(code,68192))
def propertiesBelow1355(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1352(code,U32.is_lt(code,68155))
    case False{}: propertiesBelow1354(code,U32.is_lt(code,68160))
def propertiesBelow1356(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1351(code,U32.is_lt(code,68121))
    case False{}: propertiesBelow1355(code,U32.is_lt(code,68159))
def propertiesBelow1357(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1348(code,U32.is_lt(code,68103))
    case False{}: propertiesBelow1356(code,U32.is_lt(code,68152))
def propertiesBelow1358(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1359(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1360(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1358(code,U32.is_lt(code,68224))
    case False{}: propertiesBelow1359(code,U32.is_lt(code,68288))
def propertiesBelow1361(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1362(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1363(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1362(code,U32.is_lt(code,68352))
def propertiesBelow1364(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1361(code,U32.is_lt(code,68297))
    case False{}: propertiesBelow1363(code,U32.is_lt(code,68327))
def propertiesBelow1365(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1360(code,U32.is_lt(code,68253))
    case False{}: propertiesBelow1364(code,U32.is_lt(code,68325))
def propertiesBelow1366(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1367(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1368(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1366(code,U32.is_lt(code,68416))
    case False{}: propertiesBelow1367(code,U32.is_lt(code,68448))
def propertiesBelow1369(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1370(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1371(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1370(code,U32.is_lt(code,68681))
def propertiesBelow1372(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1369(code,U32.is_lt(code,68480))
    case False{}: propertiesBelow1371(code,U32.is_lt(code,68608))
def propertiesBelow1373(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1368(code,U32.is_lt(code,68438))
    case False{}: propertiesBelow1372(code,U32.is_lt(code,68498))
def propertiesBelow1374(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1365(code,U32.is_lt(code,68296))
    case False{}: propertiesBelow1373(code,U32.is_lt(code,68467))
def propertiesBelow1375(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1357(code,U32.is_lt(code,68117))
    case False{}: propertiesBelow1374(code,U32.is_lt(code,68406))
def propertiesBelow1376(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1341(code,U32.is_lt(code,67703))
    case False{}: propertiesBelow1375(code,U32.is_lt(code,68221))
def propertiesBelow1377(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1308(code,U32.is_lt(code,66730))
    case False{}: propertiesBelow1376(code,U32.is_lt(code,68096))
def propertiesBelow1378(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1240(code,U32.is_lt(code,64434))
    case False{}: propertiesBelow1377(code,U32.is_lt(code,67463))
def propertiesBelow1379(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1380(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1381(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1379(code,U32.is_lt(code,68787))
    case False{}: propertiesBelow1380(code,U32.is_lt(code,68851))
def propertiesBelow1382(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1383(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1384(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1382(code,U32.is_lt(code,68900))
    case False{}: propertiesBelow1383(code,U32.is_lt(code,68912))
def propertiesBelow1385(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1381(code,U32.is_lt(code,68800))
    case False{}: propertiesBelow1384(code,U32.is_lt(code,68904))
def propertiesBelow1386(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1387(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1388(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1386(code,U32.is_lt(code,68928))
    case False{}: propertiesBelow1387(code,U32.is_lt(code,68966))
def propertiesBelow1389(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1390(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1391(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1390(code,U32.is_lt(code,69248))
def propertiesBelow1392(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1389(code,U32.is_lt(code,68974))
    case False{}: propertiesBelow1391(code,U32.is_lt(code,68998))
def propertiesBelow1393(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1388(code,U32.is_lt(code,68938))
    case False{}: propertiesBelow1392(code,U32.is_lt(code,68975))
def propertiesBelow1394(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1385(code,U32.is_lt(code,68864))
    case False{}: propertiesBelow1393(code,U32.is_lt(code,68969))
def propertiesBelow1395(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1396(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1397(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1395(code,U32.is_lt(code,69291))
    case False{}: propertiesBelow1396(code,U32.is_lt(code,69296))
def propertiesBelow1398(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1399(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1400(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1398(code,U32.is_lt(code,69314))
    case False{}: propertiesBelow1399(code,U32.is_lt(code,69370))
def propertiesBelow1401(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1397(code,U32.is_lt(code,69293))
    case False{}: propertiesBelow1400(code,U32.is_lt(code,69320))
def propertiesBelow1402(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1403(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1404(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1402(code,U32.is_lt(code,69405))
    case False{}: propertiesBelow1403(code,U32.is_lt(code,69416))
def propertiesBelow1405(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1406(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1407(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1406(code,U32.is_lt(code,69506))
def propertiesBelow1408(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1405(code,U32.is_lt(code,69446))
    case False{}: propertiesBelow1407(code,U32.is_lt(code,69488))
def propertiesBelow1409(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1404(code,U32.is_lt(code,69415))
    case False{}: propertiesBelow1408(code,U32.is_lt(code,69457))
def propertiesBelow1410(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1401(code,U32.is_lt(code,69298))
    case False{}: propertiesBelow1409(code,U32.is_lt(code,69424))
def propertiesBelow1411(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1394(code,U32.is_lt(code,68922))
    case False{}: propertiesBelow1410(code,U32.is_lt(code,69376))
def propertiesBelow1412(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1413(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1414(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1412(code,U32.is_lt(code,69552))
    case False{}: propertiesBelow1413(code,U32.is_lt(code,69600))
def propertiesBelow1415(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1416(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1417(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1415(code,U32.is_lt(code,69632))
    case False{}: propertiesBelow1416(code,U32.is_lt(code,69688))
def propertiesBelow1418(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1414(code,U32.is_lt(code,69573))
    case False{}: propertiesBelow1417(code,U32.is_lt(code,69635))
def propertiesBelow1419(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1420(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1421(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1419(code,U32.is_lt(code,69734))
    case False{}: propertiesBelow1420(code,U32.is_lt(code,69745))
def propertiesBelow1422(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1423(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1424(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1423(code,U32.is_lt(code,69763))
def propertiesBelow1425(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1422(code,U32.is_lt(code,69749))
    case False{}: propertiesBelow1424(code,U32.is_lt(code,69759))
def propertiesBelow1426(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1421(code,U32.is_lt(code,69744))
    case False{}: propertiesBelow1425(code,U32.is_lt(code,69750))
def propertiesBelow1427(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1418(code,U32.is_lt(code,69623))
    case False{}: propertiesBelow1426(code,U32.is_lt(code,69747))
def propertiesBelow1428(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1429(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1430(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1428(code,U32.is_lt(code,69819))
    case False{}: propertiesBelow1429(code,U32.is_lt(code,69822))
def propertiesBelow1431(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1432(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1433(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: propertiesBelow1432(code,U32.is_lt(code,69840))
def propertiesBelow1434(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1431(code,U32.is_lt(code,69827))
    case False{}: propertiesBelow1433(code,U32.is_lt(code,69838))
def propertiesBelow1435(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1430(code,U32.is_lt(code,69821))
    case False{}: propertiesBelow1434(code,U32.is_lt(code,69837))
def propertiesBelow1436(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1437(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1438(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1436(code,U32.is_lt(code,69872))
    case False{}: propertiesBelow1437(code,U32.is_lt(code,69888))
def propertiesBelow1439(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1440(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1441(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1440(code,U32.is_lt(code,69952))
def propertiesBelow1442(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1439(code,U32.is_lt(code,69927))
    case False{}: propertiesBelow1441(code,U32.is_lt(code,69942))
def propertiesBelow1443(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1438(code,U32.is_lt(code,69882))
    case False{}: propertiesBelow1442(code,U32.is_lt(code,69941))
def propertiesBelow1444(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1435(code,U32.is_lt(code,69826))
    case False{}: propertiesBelow1443(code,U32.is_lt(code,69891))
def propertiesBelow1445(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1427(code,U32.is_lt(code,69703))
    case False{}: propertiesBelow1444(code,U32.is_lt(code,69865))
def propertiesBelow1446(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1411(code,U32.is_lt(code,69290))
    case False{}: propertiesBelow1445(code,U32.is_lt(code,69808))
def propertiesBelow1447(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1448(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1449(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1447(code,U32.is_lt(code,69957))
    case False{}: propertiesBelow1448(code,U32.is_lt(code,69960))
def propertiesBelow1450(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1451(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1452(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1450(code,U32.is_lt(code,70003))
    case False{}: propertiesBelow1451(code,U32.is_lt(code,70006))
def propertiesBelow1453(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1449(code,U32.is_lt(code,69959))
    case False{}: propertiesBelow1452(code,U32.is_lt(code,70004))
def propertiesBelow1454(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1455(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1456(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1454(code,U32.is_lt(code,70016))
    case False{}: propertiesBelow1455(code,U32.is_lt(code,70067))
def propertiesBelow1457(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1458(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1459(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1458(code,U32.is_lt(code,70094))
def propertiesBelow1460(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1457(code,U32.is_lt(code,70085))
    case False{}: propertiesBelow1459(code,U32.is_lt(code,70093))
def propertiesBelow1461(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1456(code,U32.is_lt(code,70019))
    case False{}: propertiesBelow1460(code,U32.is_lt(code,70089))
def propertiesBelow1462(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1453(code,U32.is_lt(code,69968))
    case False{}: propertiesBelow1461(code,U32.is_lt(code,70081))
def propertiesBelow1463(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 8
def propertiesBelow1464(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1465(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1463(code,U32.is_lt(code,70106))
    case False{}: propertiesBelow1464(code,U32.is_lt(code,70108))
def propertiesBelow1466(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1467(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1468(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1466(code,U32.is_lt(code,70144))
    case False{}: propertiesBelow1467(code,U32.is_lt(code,70163))
def propertiesBelow1469(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1465(code,U32.is_lt(code,70107))
    case False{}: propertiesBelow1468(code,U32.is_lt(code,70162))
def propertiesBelow1470(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1471(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1472(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1470(code,U32.is_lt(code,70200))
    case False{}: propertiesBelow1471(code,U32.is_lt(code,70207))
def propertiesBelow1473(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1474(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1475(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1474(code,U32.is_lt(code,70280))
def propertiesBelow1476(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1473(code,U32.is_lt(code,70210))
    case False{}: propertiesBelow1475(code,U32.is_lt(code,70279))
def propertiesBelow1477(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1472(code,U32.is_lt(code,70206))
    case False{}: propertiesBelow1476(code,U32.is_lt(code,70272))
def propertiesBelow1478(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1469(code,U32.is_lt(code,70109))
    case False{}: propertiesBelow1477(code,U32.is_lt(code,70209))
def propertiesBelow1479(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1462(code,U32.is_lt(code,70007))
    case False{}: propertiesBelow1478(code,U32.is_lt(code,70188))
def propertiesBelow1480(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1481(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1482(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1480(code,U32.is_lt(code,70282))
    case False{}: propertiesBelow1481(code,U32.is_lt(code,70287))
def propertiesBelow1483(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1484(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1485(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1483(code,U32.is_lt(code,70303))
    case False{}: propertiesBelow1484(code,U32.is_lt(code,70320))
def propertiesBelow1486(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1482(code,U32.is_lt(code,70286))
    case False{}: propertiesBelow1485(code,U32.is_lt(code,70313))
def propertiesBelow1487(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1488(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1489(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1487(code,U32.is_lt(code,70379))
    case False{}: propertiesBelow1488(code,U32.is_lt(code,70394))
def propertiesBelow1490(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1491(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1492(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1491(code,U32.is_lt(code,70415))
def propertiesBelow1493(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1490(code,U32.is_lt(code,70404))
    case False{}: propertiesBelow1492(code,U32.is_lt(code,70413))
def propertiesBelow1494(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1489(code,U32.is_lt(code,70384))
    case False{}: propertiesBelow1493(code,U32.is_lt(code,70405))
def propertiesBelow1495(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1486(code,U32.is_lt(code,70302))
    case False{}: propertiesBelow1494(code,U32.is_lt(code,70400))
def propertiesBelow1496(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1497(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1498(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1496(code,U32.is_lt(code,70419))
    case False{}: propertiesBelow1497(code,U32.is_lt(code,70442))
def propertiesBelow1499(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1500(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1501(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1500(code,U32.is_lt(code,70458))
def propertiesBelow1502(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1499(code,U32.is_lt(code,70450))
    case False{}: propertiesBelow1501(code,U32.is_lt(code,70453))
def propertiesBelow1503(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1498(code,U32.is_lt(code,70441))
    case False{}: propertiesBelow1502(code,U32.is_lt(code,70452))
def propertiesBelow1504(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1505(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1506(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1504(code,U32.is_lt(code,70461))
    case False{}: propertiesBelow1505(code,U32.is_lt(code,70469))
def propertiesBelow1507(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1508(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1509(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1508(code,U32.is_lt(code,70480))
def propertiesBelow1510(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1507(code,U32.is_lt(code,70473))
    case False{}: propertiesBelow1509(code,U32.is_lt(code,70478))
def propertiesBelow1511(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1506(code,U32.is_lt(code,70462))
    case False{}: propertiesBelow1510(code,U32.is_lt(code,70475))
def propertiesBelow1512(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1503(code,U32.is_lt(code,70449))
    case False{}: propertiesBelow1511(code,U32.is_lt(code,70471))
def propertiesBelow1513(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1495(code,U32.is_lt(code,70367))
    case False{}: propertiesBelow1512(code,U32.is_lt(code,70459))
def propertiesBelow1514(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1479(code,U32.is_lt(code,70096))
    case False{}: propertiesBelow1513(code,U32.is_lt(code,70417))
def propertiesBelow1515(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1446(code,U32.is_lt(code,69510))
    case False{}: propertiesBelow1514(code,U32.is_lt(code,70281))
def propertiesBelow1516(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1517(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1518(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1516(code,U32.is_lt(code,70487))
    case False{}: propertiesBelow1517(code,U32.is_lt(code,70493))
def propertiesBelow1519(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1520(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1521(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1519(code,U32.is_lt(code,70500))
    case False{}: propertiesBelow1520(code,U32.is_lt(code,70509))
def propertiesBelow1522(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1518(code,U32.is_lt(code,70488))
    case False{}: propertiesBelow1521(code,U32.is_lt(code,70502))
def propertiesBelow1523(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1524(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1525(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1523(code,U32.is_lt(code,70517))
    case False{}: propertiesBelow1524(code,U32.is_lt(code,70538))
def propertiesBelow1526(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1527(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1528(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1527(code,U32.is_lt(code,70544))
def propertiesBelow1529(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1526(code,U32.is_lt(code,70540))
    case False{}: propertiesBelow1528(code,U32.is_lt(code,70543))
def propertiesBelow1530(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1525(code,U32.is_lt(code,70528))
    case False{}: propertiesBelow1529(code,U32.is_lt(code,70542))
def propertiesBelow1531(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1522(code,U32.is_lt(code,70498))
    case False{}: propertiesBelow1530(code,U32.is_lt(code,70539))
def propertiesBelow1532(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1533(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1534(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1532(code,U32.is_lt(code,70583))
    case False{}: propertiesBelow1533(code,U32.is_lt(code,70593))
def propertiesBelow1535(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1536(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1537(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1535(code,U32.is_lt(code,70595))
    case False{}: propertiesBelow1536(code,U32.is_lt(code,70598))
def propertiesBelow1538(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1534(code,U32.is_lt(code,70584))
    case False{}: propertiesBelow1537(code,U32.is_lt(code,70597))
def propertiesBelow1539(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1540(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1541(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1539(code,U32.is_lt(code,70603))
    case False{}: propertiesBelow1540(code,U32.is_lt(code,70609))
def propertiesBelow1542(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1543(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1544(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1543(code,U32.is_lt(code,70627))
def propertiesBelow1545(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1542(code,U32.is_lt(code,70611))
    case False{}: propertiesBelow1544(code,U32.is_lt(code,70625))
def propertiesBelow1546(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1541(code,U32.is_lt(code,70604))
    case False{}: propertiesBelow1545(code,U32.is_lt(code,70612))
def propertiesBelow1547(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1538(code,U32.is_lt(code,70594))
    case False{}: propertiesBelow1546(code,U32.is_lt(code,70610))
def propertiesBelow1548(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1531(code,U32.is_lt(code,70512))
    case False{}: propertiesBelow1547(code,U32.is_lt(code,70599))
def propertiesBelow1549(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1550(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1551(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1549(code,U32.is_lt(code,70709))
    case False{}: propertiesBelow1550(code,U32.is_lt(code,70731))
def propertiesBelow1552(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1553(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1554(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1552(code,U32.is_lt(code,70746))
    case False{}: propertiesBelow1553(code,U32.is_lt(code,70751))
def propertiesBelow1555(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1551(code,U32.is_lt(code,70727))
    case False{}: propertiesBelow1554(code,U32.is_lt(code,70750))
def propertiesBelow1556(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1557(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1558(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1556(code,U32.is_lt(code,70784))
    case False{}: propertiesBelow1557(code,U32.is_lt(code,70852))
def propertiesBelow1559(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1560(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1561(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1560(code,U32.is_lt(code,70874))
def propertiesBelow1562(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1559(code,U32.is_lt(code,70855))
    case False{}: propertiesBelow1561(code,U32.is_lt(code,70864))
def propertiesBelow1563(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1558(code,U32.is_lt(code,70832))
    case False{}: propertiesBelow1562(code,U32.is_lt(code,70856))
def propertiesBelow1564(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1555(code,U32.is_lt(code,70736))
    case False{}: propertiesBelow1563(code,U32.is_lt(code,70854))
def propertiesBelow1565(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1566(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1567(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1565(code,U32.is_lt(code,71087))
    case False{}: propertiesBelow1566(code,U32.is_lt(code,71096))
def propertiesBelow1568(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1569(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1570(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1569(code,U32.is_lt(code,71168))
def propertiesBelow1571(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1568(code,U32.is_lt(code,71128))
    case False{}: propertiesBelow1570(code,U32.is_lt(code,71134))
def propertiesBelow1572(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1567(code,U32.is_lt(code,71094))
    case False{}: propertiesBelow1571(code,U32.is_lt(code,71132))
def propertiesBelow1573(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1574(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1575(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1573(code,U32.is_lt(code,71233))
    case False{}: propertiesBelow1574(code,U32.is_lt(code,71237))
def propertiesBelow1576(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1577(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1578(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1577(code,U32.is_lt(code,71352))
def propertiesBelow1579(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1576(code,U32.is_lt(code,71258))
    case False{}: propertiesBelow1578(code,U32.is_lt(code,71339))
def propertiesBelow1580(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1575(code,U32.is_lt(code,71236))
    case False{}: propertiesBelow1579(code,U32.is_lt(code,71296))
def propertiesBelow1581(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1572(code,U32.is_lt(code,71105))
    case False{}: propertiesBelow1580(code,U32.is_lt(code,71248))
def propertiesBelow1582(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1564(code,U32.is_lt(code,70754))
    case False{}: propertiesBelow1581(code,U32.is_lt(code,71216))
def propertiesBelow1583(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1548(code,U32.is_lt(code,70582))
    case False{}: propertiesBelow1582(code,U32.is_lt(code,71040))
def propertiesBelow1584(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1585(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1586(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1584(code,U32.is_lt(code,71360))
    case False{}: propertiesBelow1585(code,U32.is_lt(code,71376))
def propertiesBelow1587(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1588(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1589(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1587(code,U32.is_lt(code,71453))
    case False{}: propertiesBelow1588(code,U32.is_lt(code,71472))
def propertiesBelow1590(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1586(code,U32.is_lt(code,71370))
    case False{}: propertiesBelow1589(code,U32.is_lt(code,71468))
def propertiesBelow1591(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1592(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1593(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1591(code,U32.is_lt(code,71680))
    case False{}: propertiesBelow1592(code,U32.is_lt(code,71739))
def propertiesBelow1594(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow1595(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1596(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1595(code,U32.is_lt(code,71943))
def propertiesBelow1597(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1594(code,U32.is_lt(code,71904))
    case False{}: propertiesBelow1596(code,U32.is_lt(code,71935))
def propertiesBelow1598(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1593(code,U32.is_lt(code,71724))
    case False{}: propertiesBelow1597(code,U32.is_lt(code,71914))
def propertiesBelow1599(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1590(code,U32.is_lt(code,71396))
    case False{}: propertiesBelow1598(code,U32.is_lt(code,71840))
def propertiesBelow1600(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1601(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1602(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1600(code,U32.is_lt(code,71946))
    case False{}: propertiesBelow1601(code,U32.is_lt(code,71956))
def propertiesBelow1603(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1604(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1605(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1604(code,U32.is_lt(code,71990))
def propertiesBelow1606(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1603(code,U32.is_lt(code,71959))
    case False{}: propertiesBelow1605(code,U32.is_lt(code,71984))
def propertiesBelow1607(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1602(code,U32.is_lt(code,71948))
    case False{}: propertiesBelow1606(code,U32.is_lt(code,71960))
def propertiesBelow1608(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1609(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1610(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1608(code,U32.is_lt(code,71993))
    case False{}: propertiesBelow1609(code,U32.is_lt(code,71999))
def propertiesBelow1611(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1612(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1613(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1612(code,U32.is_lt(code,72016))
def propertiesBelow1614(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1611(code,U32.is_lt(code,72001))
    case False{}: propertiesBelow1613(code,U32.is_lt(code,72004))
def propertiesBelow1615(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1610(code,U32.is_lt(code,71995))
    case False{}: propertiesBelow1614(code,U32.is_lt(code,72002))
def propertiesBelow1616(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1607(code,U32.is_lt(code,71957))
    case False{}: propertiesBelow1615(code,U32.is_lt(code,72000))
def propertiesBelow1617(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1599(code,U32.is_lt(code,71482))
    case False{}: propertiesBelow1616(code,U32.is_lt(code,71991))
def propertiesBelow1618(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1619(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1620(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1618(code,U32.is_lt(code,72096))
    case False{}: propertiesBelow1619(code,U32.is_lt(code,72106))
def propertiesBelow1621(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1622(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1623(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1621(code,U32.is_lt(code,72152))
    case False{}: propertiesBelow1622(code,U32.is_lt(code,72161))
def propertiesBelow1624(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1620(code,U32.is_lt(code,72104))
    case False{}: propertiesBelow1623(code,U32.is_lt(code,72154))
def propertiesBelow1625(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1626(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1627(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1625(code,U32.is_lt(code,72163))
    case False{}: propertiesBelow1626(code,U32.is_lt(code,72165))
def propertiesBelow1628(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1629(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1630(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1629(code,U32.is_lt(code,72250))
def propertiesBelow1631(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1628(code,U32.is_lt(code,72193))
    case False{}: propertiesBelow1630(code,U32.is_lt(code,72243))
def propertiesBelow1632(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1627(code,U32.is_lt(code,72164))
    case False{}: propertiesBelow1631(code,U32.is_lt(code,72203))
def propertiesBelow1633(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1624(code,U32.is_lt(code,72145))
    case False{}: propertiesBelow1632(code,U32.is_lt(code,72192))
def propertiesBelow1634(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1635(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1636(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1634(code,U32.is_lt(code,72255))
    case False{}: propertiesBelow1635(code,U32.is_lt(code,72264))
def propertiesBelow1637(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1638(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1639(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1638(code,U32.is_lt(code,72346))
def propertiesBelow1640(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1637(code,U32.is_lt(code,72273))
    case False{}: propertiesBelow1639(code,U32.is_lt(code,72330))
def propertiesBelow1641(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1636(code,U32.is_lt(code,72263))
    case False{}: propertiesBelow1640(code,U32.is_lt(code,72284))
def propertiesBelow1642(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1643(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1644(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1642(code,U32.is_lt(code,72350))
    case False{}: propertiesBelow1643(code,U32.is_lt(code,72441))
def propertiesBelow1645(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1646(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1647(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1646(code,U32.is_lt(code,72688))
def propertiesBelow1648(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1645(code,U32.is_lt(code,72552))
    case False{}: propertiesBelow1647(code,U32.is_lt(code,72673))
def propertiesBelow1649(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1644(code,U32.is_lt(code,72368))
    case False{}: propertiesBelow1648(code,U32.is_lt(code,72640))
def propertiesBelow1650(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1641(code,U32.is_lt(code,72272))
    case False{}: propertiesBelow1649(code,U32.is_lt(code,72544))
def propertiesBelow1651(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1633(code,U32.is_lt(code,72162))
    case False{}: propertiesBelow1650(code,U32.is_lt(code,72349))
def propertiesBelow1652(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1617(code,U32.is_lt(code,71945))
    case False{}: propertiesBelow1651(code,U32.is_lt(code,72251))
def propertiesBelow1653(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1583(code,U32.is_lt(code,70656))
    case False{}: propertiesBelow1652(code,U32.is_lt(code,72026))
def propertiesBelow1654(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1515(code,U32.is_lt(code,69956))
    case False{}: propertiesBelow1653(code,U32.is_lt(code,71353))
def propertiesBelow1655(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1378(code,U32.is_lt(code,65599))
    case False{}: propertiesBelow1654(code,U32.is_lt(code,70481))
def propertiesBelow1656(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1657(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1658(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1656(code,U32.is_lt(code,72704))
    case False{}: propertiesBelow1657(code,U32.is_lt(code,72714))
def propertiesBelow1659(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1660(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1661(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1659(code,U32.is_lt(code,72759))
    case False{}: propertiesBelow1660(code,U32.is_lt(code,72768))
def propertiesBelow1662(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1658(code,U32.is_lt(code,72713))
    case False{}: propertiesBelow1661(code,U32.is_lt(code,72760))
def propertiesBelow1663(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1664(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1665(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1663(code,U32.is_lt(code,72784))
    case False{}: propertiesBelow1664(code,U32.is_lt(code,72818))
def propertiesBelow1666(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1667(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1668(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1667(code,U32.is_lt(code,72887))
def propertiesBelow1669(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1666(code,U32.is_lt(code,72850))
    case False{}: propertiesBelow1668(code,U32.is_lt(code,72873))
def propertiesBelow1670(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1665(code,U32.is_lt(code,72794))
    case False{}: propertiesBelow1669(code,U32.is_lt(code,72872))
def propertiesBelow1671(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1662(code,U32.is_lt(code,72751))
    case False{}: propertiesBelow1670(code,U32.is_lt(code,72848))
def propertiesBelow1672(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1673(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1674(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1672(code,U32.is_lt(code,72967))
    case False{}: propertiesBelow1673(code,U32.is_lt(code,72970))
def propertiesBelow1675(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1676(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1677(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1675(code,U32.is_lt(code,73009))
    case False{}: propertiesBelow1676(code,U32.is_lt(code,73018))
def propertiesBelow1678(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1674(code,U32.is_lt(code,72968))
    case False{}: propertiesBelow1677(code,U32.is_lt(code,73015))
def propertiesBelow1679(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1680(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1681(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1679(code,U32.is_lt(code,73020))
    case False{}: propertiesBelow1680(code,U32.is_lt(code,73023))
def propertiesBelow1682(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1683(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1684(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1683(code,U32.is_lt(code,73050))
def propertiesBelow1685(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1682(code,U32.is_lt(code,73031))
    case False{}: propertiesBelow1684(code,U32.is_lt(code,73040))
def propertiesBelow1686(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1681(code,U32.is_lt(code,73022))
    case False{}: propertiesBelow1685(code,U32.is_lt(code,73032))
def propertiesBelow1687(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1678(code,U32.is_lt(code,72971))
    case False{}: propertiesBelow1686(code,U32.is_lt(code,73030))
def propertiesBelow1688(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1671(code,U32.is_lt(code,72769))
    case False{}: propertiesBelow1687(code,U32.is_lt(code,73019))
def propertiesBelow1689(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1690(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1691(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1689(code,U32.is_lt(code,73062))
    case False{}: propertiesBelow1690(code,U32.is_lt(code,73065))
def propertiesBelow1692(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1693(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1694(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1692(code,U32.is_lt(code,73098))
    case False{}: propertiesBelow1693(code,U32.is_lt(code,73104))
def propertiesBelow1695(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1691(code,U32.is_lt(code,73063))
    case False{}: propertiesBelow1694(code,U32.is_lt(code,73103))
def propertiesBelow1696(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1697(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1698(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1696(code,U32.is_lt(code,73107))
    case False{}: propertiesBelow1697(code,U32.is_lt(code,73113))
def propertiesBelow1699(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1700(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1701(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1700(code,U32.is_lt(code,73184))
def propertiesBelow1702(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1699(code,U32.is_lt(code,73130))
    case False{}: propertiesBelow1701(code,U32.is_lt(code,73180))
def propertiesBelow1703(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1698(code,U32.is_lt(code,73112))
    case False{}: propertiesBelow1702(code,U32.is_lt(code,73136))
def propertiesBelow1704(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1695(code,U32.is_lt(code,73066))
    case False{}: propertiesBelow1703(code,U32.is_lt(code,73120))
def propertiesBelow1705(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1706(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1707(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1705(code,U32.is_lt(code,73440))
    case False{}: propertiesBelow1706(code,U32.is_lt(code,73463))
def propertiesBelow1708(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1709(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1710(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1709(code,U32.is_lt(code,73489))
def propertiesBelow1711(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1708(code,U32.is_lt(code,73474))
    case False{}: propertiesBelow1710(code,U32.is_lt(code,73476))
def propertiesBelow1712(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1707(code,U32.is_lt(code,73459))
    case False{}: propertiesBelow1711(code,U32.is_lt(code,73475))
def propertiesBelow1713(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1714(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1715(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1713(code,U32.is_lt(code,73524))
    case False{}: propertiesBelow1714(code,U32.is_lt(code,73534))
def propertiesBelow1716(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1717(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1718(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1717(code,U32.is_lt(code,73648))
def propertiesBelow1719(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1716(code,U32.is_lt(code,73552))
    case False{}: propertiesBelow1718(code,U32.is_lt(code,73563))
def propertiesBelow1720(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1715(code,U32.is_lt(code,73531))
    case False{}: propertiesBelow1719(code,U32.is_lt(code,73562))
def propertiesBelow1721(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1712(code,U32.is_lt(code,73472))
    case False{}: propertiesBelow1720(code,U32.is_lt(code,73539))
def propertiesBelow1722(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1704(code,U32.is_lt(code,73106))
    case False{}: propertiesBelow1721(code,U32.is_lt(code,73490))
def propertiesBelow1723(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1688(code,U32.is_lt(code,72960))
    case False{}: propertiesBelow1722(code,U32.is_lt(code,73194))
def propertiesBelow1724(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1725(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1726(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1724(code,U32.is_lt(code,73728))
    case False{}: propertiesBelow1725(code,U32.is_lt(code,74752))
def propertiesBelow1727(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1728(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1729(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1727(code,U32.is_lt(code,74880))
    case False{}: propertiesBelow1728(code,U32.is_lt(code,77712))
def propertiesBelow1730(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1726(code,U32.is_lt(code,74650))
    case False{}: propertiesBelow1729(code,U32.is_lt(code,75076))
def propertiesBelow1731(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1732(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 4
def propertiesBelow1733(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1731(code,U32.is_lt(code,77824))
    case False{}: propertiesBelow1732(code,U32.is_lt(code,78912))
def propertiesBelow1734(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1735(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1736(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1735(code,U32.is_lt(code,82939))
def propertiesBelow1737(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1734(code,U32.is_lt(code,78919))
    case False{}: propertiesBelow1736(code,U32.is_lt(code,78944))
def propertiesBelow1738(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1733(code,U32.is_lt(code,78896))
    case False{}: propertiesBelow1737(code,U32.is_lt(code,78934))
def propertiesBelow1739(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1730(code,U32.is_lt(code,74863))
    case False{}: propertiesBelow1738(code,U32.is_lt(code,78913))
def propertiesBelow1740(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1741(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1742(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1740(code,U32.is_lt(code,83527))
    case False{}: propertiesBelow1741(code,U32.is_lt(code,90398))
def propertiesBelow1743(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1744(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1745(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1743(code,U32.is_lt(code,90426))
    case False{}: propertiesBelow1744(code,U32.is_lt(code,92729))
def propertiesBelow1746(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1742(code,U32.is_lt(code,90368))
    case False{}: propertiesBelow1745(code,U32.is_lt(code,92160))
def propertiesBelow1747(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1748(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1749(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1747(code,U32.is_lt(code,92767))
    case False{}: propertiesBelow1748(code,U32.is_lt(code,92778))
def propertiesBelow1750(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1751(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1752(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: propertiesBelow1751(code,U32.is_lt(code,92880))
def propertiesBelow1753(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1750(code,U32.is_lt(code,92863))
    case False{}: propertiesBelow1752(code,U32.is_lt(code,92874))
def propertiesBelow1754(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1749(code,U32.is_lt(code,92768))
    case False{}: propertiesBelow1753(code,U32.is_lt(code,92864))
def propertiesBelow1755(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1746(code,U32.is_lt(code,90416))
    case False{}: propertiesBelow1754(code,U32.is_lt(code,92784))
def propertiesBelow1756(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1739(code,U32.is_lt(code,77809))
    case False{}: propertiesBelow1755(code,U32.is_lt(code,92736))
def propertiesBelow1757(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1758(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1759(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1757(code,U32.is_lt(code,92912))
    case False{}: propertiesBelow1758(code,U32.is_lt(code,92928))
def propertiesBelow1760(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1761(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1762(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1760(code,U32.is_lt(code,92983))
    case False{}: propertiesBelow1761(code,U32.is_lt(code,92996))
def propertiesBelow1763(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1759(code,U32.is_lt(code,92917))
    case False{}: propertiesBelow1762(code,U32.is_lt(code,92992))
def propertiesBelow1764(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1765(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1766(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1764(code,U32.is_lt(code,93018))
    case False{}: propertiesBelow1765(code,U32.is_lt(code,93048))
def propertiesBelow1767(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1768(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow1769(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1768(code,U32.is_lt(code,93552))
def propertiesBelow1770(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1767(code,U32.is_lt(code,93072))
    case False{}: propertiesBelow1769(code,U32.is_lt(code,93549))
def propertiesBelow1771(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1766(code,U32.is_lt(code,93027))
    case False{}: propertiesBelow1770(code,U32.is_lt(code,93504))
def propertiesBelow1772(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1763(code,U32.is_lt(code,92976))
    case False{}: propertiesBelow1771(code,U32.is_lt(code,93053))
def propertiesBelow1773(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1774(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1775(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1773(code,U32.is_lt(code,93760))
    case False{}: propertiesBelow1774(code,U32.is_lt(code,93856))
def propertiesBelow1776(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1777(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1778(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1777(code,U32.is_lt(code,94027))
def propertiesBelow1779(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1776(code,U32.is_lt(code,93883))
    case False{}: propertiesBelow1778(code,U32.is_lt(code,93952))
def propertiesBelow1780(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1775(code,U32.is_lt(code,93824))
    case False{}: propertiesBelow1779(code,U32.is_lt(code,93908))
def propertiesBelow1781(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1782(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1783(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1781(code,U32.is_lt(code,94032))
    case False{}: propertiesBelow1782(code,U32.is_lt(code,94088))
def propertiesBelow1784(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 8
def propertiesBelow1785(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1786(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1785(code,U32.is_lt(code,94178))
def propertiesBelow1787(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1784(code,U32.is_lt(code,94099))
    case False{}: propertiesBelow1786(code,U32.is_lt(code,94176))
def propertiesBelow1788(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1783(code,U32.is_lt(code,94033))
    case False{}: propertiesBelow1787(code,U32.is_lt(code,94112))
def propertiesBelow1789(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1780(code,U32.is_lt(code,93881))
    case False{}: propertiesBelow1788(code,U32.is_lt(code,94095))
def propertiesBelow1790(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1772(code,U32.is_lt(code,93008))
    case False{}: propertiesBelow1789(code,U32.is_lt(code,94031))
def propertiesBelow1791(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1756(code,U32.is_lt(code,82944))
    case False{}: propertiesBelow1790(code,U32.is_lt(code,93562))
def propertiesBelow1792(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1723(code,U32.is_lt(code,73056))
    case False{}: propertiesBelow1791(code,U32.is_lt(code,92910))
def propertiesBelow1793(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1794(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1795(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1793(code,U32.is_lt(code,94180))
    case False{}: propertiesBelow1794(code,U32.is_lt(code,94192))
def propertiesBelow1796(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1797(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1798(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1796(code,U32.is_lt(code,110576))
    case False{}: propertiesBelow1797(code,U32.is_lt(code,110581))
def propertiesBelow1799(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1795(code,U32.is_lt(code,94181))
    case False{}: propertiesBelow1798(code,U32.is_lt(code,110580))
def propertiesBelow1800(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1801(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1802(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1800(code,U32.is_lt(code,110589))
    case False{}: propertiesBelow1801(code,U32.is_lt(code,110592))
def propertiesBelow1803(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 11
def propertiesBelow1804(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 11
    case False{}: 0
def propertiesBelow1805(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1804(code,U32.is_lt(code,110934))
def propertiesBelow1806(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1803(code,U32.is_lt(code,110880))
    case False{}: propertiesBelow1805(code,U32.is_lt(code,110933))
def propertiesBelow1807(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1802(code,U32.is_lt(code,110591))
    case False{}: propertiesBelow1806(code,U32.is_lt(code,110883))
def propertiesBelow1808(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1799(code,U32.is_lt(code,94194))
    case False{}: propertiesBelow1807(code,U32.is_lt(code,110593))
def propertiesBelow1809(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 11
    case False{}: 0
def propertiesBelow1810(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1811(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1809(code,U32.is_lt(code,110952))
    case False{}: propertiesBelow1810(code,U32.is_lt(code,113771))
def propertiesBelow1812(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1813(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1814(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1812(code,U32.is_lt(code,113789))
    case False{}: propertiesBelow1813(code,U32.is_lt(code,113801))
def propertiesBelow1815(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1811(code,U32.is_lt(code,113664))
    case False{}: propertiesBelow1814(code,U32.is_lt(code,113792))
def propertiesBelow1816(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1817(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1818(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1816(code,U32.is_lt(code,113818))
    case False{}: propertiesBelow1817(code,U32.is_lt(code,113823))
def propertiesBelow1819(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 0
def propertiesBelow1820(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1821(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: propertiesBelow1820(code,U32.is_lt(code,118528))
def propertiesBelow1822(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1819(code,U32.is_lt(code,113828))
    case False{}: propertiesBelow1821(code,U32.is_lt(code,118010))
def propertiesBelow1823(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1818(code,U32.is_lt(code,113821))
    case False{}: propertiesBelow1822(code,U32.is_lt(code,118000))
def propertiesBelow1824(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1815(code,U32.is_lt(code,113776))
    case False{}: propertiesBelow1823(code,U32.is_lt(code,113824))
def propertiesBelow1825(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1808(code,U32.is_lt(code,110588))
    case False{}: propertiesBelow1824(code,U32.is_lt(code,113808))
def propertiesBelow1826(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1827(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1828(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1826(code,U32.is_lt(code,118576))
    case False{}: propertiesBelow1827(code,U32.is_lt(code,119141))
def propertiesBelow1829(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1830(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 5
    case False{}: 4
def propertiesBelow1831(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1829(code,U32.is_lt(code,119149))
    case False{}: propertiesBelow1830(code,U32.is_lt(code,119163))
def propertiesBelow1832(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1828(code,U32.is_lt(code,118599))
    case False{}: propertiesBelow1831(code,U32.is_lt(code,119155))
def propertiesBelow1833(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1834(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1835(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1833(code,U32.is_lt(code,119173))
    case False{}: propertiesBelow1834(code,U32.is_lt(code,119210))
def propertiesBelow1836(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1837(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1838(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1837(code,U32.is_lt(code,119893))
def propertiesBelow1839(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1836(code,U32.is_lt(code,119362))
    case False{}: propertiesBelow1838(code,U32.is_lt(code,119808))
def propertiesBelow1840(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1835(code,U32.is_lt(code,119180))
    case False{}: propertiesBelow1839(code,U32.is_lt(code,119365))
def propertiesBelow1841(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1832(code,U32.is_lt(code,119146))
    case False{}: propertiesBelow1840(code,U32.is_lt(code,119214))
def propertiesBelow1842(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1843(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1844(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1842(code,U32.is_lt(code,119965))
    case False{}: propertiesBelow1843(code,U32.is_lt(code,119968))
def propertiesBelow1845(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1846(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1847(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1846(code,U32.is_lt(code,119977))
def propertiesBelow1848(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1845(code,U32.is_lt(code,119971))
    case False{}: propertiesBelow1847(code,U32.is_lt(code,119975))
def propertiesBelow1849(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1844(code,U32.is_lt(code,119966))
    case False{}: propertiesBelow1848(code,U32.is_lt(code,119973))
def propertiesBelow1850(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1851(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1852(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1850(code,U32.is_lt(code,119982))
    case False{}: propertiesBelow1851(code,U32.is_lt(code,119995))
def propertiesBelow1853(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1854(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1855(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1854(code,U32.is_lt(code,120070))
def propertiesBelow1856(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1853(code,U32.is_lt(code,119997))
    case False{}: propertiesBelow1855(code,U32.is_lt(code,120005))
def propertiesBelow1857(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1852(code,U32.is_lt(code,119994))
    case False{}: propertiesBelow1856(code,U32.is_lt(code,120004))
def propertiesBelow1858(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1849(code,U32.is_lt(code,119970))
    case False{}: propertiesBelow1857(code,U32.is_lt(code,119996))
def propertiesBelow1859(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1841(code,U32.is_lt(code,119171))
    case False{}: propertiesBelow1858(code,U32.is_lt(code,119981))
def propertiesBelow1860(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1825(code,U32.is_lt(code,110948))
    case False{}: propertiesBelow1859(code,U32.is_lt(code,119894))
def propertiesBelow1861(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1862(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1863(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1861(code,U32.is_lt(code,120075))
    case False{}: propertiesBelow1862(code,U32.is_lt(code,120085))
def propertiesBelow1864(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1865(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1866(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1864(code,U32.is_lt(code,120093))
    case False{}: propertiesBelow1865(code,U32.is_lt(code,120122))
def propertiesBelow1867(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1863(code,U32.is_lt(code,120077))
    case False{}: propertiesBelow1866(code,U32.is_lt(code,120094))
def propertiesBelow1868(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1869(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1870(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1868(code,U32.is_lt(code,120127))
    case False{}: propertiesBelow1869(code,U32.is_lt(code,120133))
def propertiesBelow1871(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1872(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1873(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow1872(code,U32.is_lt(code,120146))
def propertiesBelow1874(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1871(code,U32.is_lt(code,120135))
    case False{}: propertiesBelow1873(code,U32.is_lt(code,120145))
def propertiesBelow1875(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1870(code,U32.is_lt(code,120128))
    case False{}: propertiesBelow1874(code,U32.is_lt(code,120138))
def propertiesBelow1876(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1867(code,U32.is_lt(code,120086))
    case False{}: propertiesBelow1875(code,U32.is_lt(code,120134))
def propertiesBelow1877(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1878(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1879(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1877(code,U32.is_lt(code,120488))
    case False{}: propertiesBelow1878(code,U32.is_lt(code,120514))
def propertiesBelow1880(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1881(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1882(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1880(code,U32.is_lt(code,120540))
    case False{}: propertiesBelow1881(code,U32.is_lt(code,120572))
def propertiesBelow1883(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1879(code,U32.is_lt(code,120513))
    case False{}: propertiesBelow1882(code,U32.is_lt(code,120571))
def propertiesBelow1884(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1885(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1886(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1884(code,U32.is_lt(code,120598))
    case False{}: propertiesBelow1885(code,U32.is_lt(code,120630))
def propertiesBelow1887(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1888(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1889(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1888(code,U32.is_lt(code,120713))
def propertiesBelow1890(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1887(code,U32.is_lt(code,120656))
    case False{}: propertiesBelow1889(code,U32.is_lt(code,120688))
def propertiesBelow1891(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1886(code,U32.is_lt(code,120629))
    case False{}: propertiesBelow1890(code,U32.is_lt(code,120687))
def propertiesBelow1892(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1883(code,U32.is_lt(code,120539))
    case False{}: propertiesBelow1891(code,U32.is_lt(code,120655))
def propertiesBelow1893(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1876(code,U32.is_lt(code,120123))
    case False{}: propertiesBelow1892(code,U32.is_lt(code,120597))
def propertiesBelow1894(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1895(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1896(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1894(code,U32.is_lt(code,120745))
    case False{}: propertiesBelow1895(code,U32.is_lt(code,120771))
def propertiesBelow1897(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1898(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1899(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1897(code,U32.is_lt(code,120780))
    case False{}: propertiesBelow1898(code,U32.is_lt(code,120832))
def propertiesBelow1900(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1896(code,U32.is_lt(code,120746))
    case False{}: propertiesBelow1899(code,U32.is_lt(code,120782))
def propertiesBelow1901(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1902(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1903(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1901(code,U32.is_lt(code,121399))
    case False{}: propertiesBelow1902(code,U32.is_lt(code,121453))
def propertiesBelow1904(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1905(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1906(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1905(code,U32.is_lt(code,121499))
def propertiesBelow1907(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1904(code,U32.is_lt(code,121462))
    case False{}: propertiesBelow1906(code,U32.is_lt(code,121477))
def propertiesBelow1908(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1903(code,U32.is_lt(code,121403))
    case False{}: propertiesBelow1907(code,U32.is_lt(code,121476))
def propertiesBelow1909(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1900(code,U32.is_lt(code,120772))
    case False{}: propertiesBelow1908(code,U32.is_lt(code,121461))
def propertiesBelow1910(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1911(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1912(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1910(code,U32.is_lt(code,121505))
    case False{}: propertiesBelow1911(code,U32.is_lt(code,122624))
def propertiesBelow1913(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1914(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1915(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1914(code,U32.is_lt(code,122887))
def propertiesBelow1916(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1913(code,U32.is_lt(code,122661))
    case False{}: propertiesBelow1915(code,U32.is_lt(code,122880))
def propertiesBelow1917(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1912(code,U32.is_lt(code,121520))
    case False{}: propertiesBelow1916(code,U32.is_lt(code,122667))
def propertiesBelow1918(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1919(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1920(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1918(code,U32.is_lt(code,122905))
    case False{}: propertiesBelow1919(code,U32.is_lt(code,122914))
def propertiesBelow1921(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1922(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1923(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1922(code,U32.is_lt(code,122928))
def propertiesBelow1924(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1921(code,U32.is_lt(code,122917))
    case False{}: propertiesBelow1923(code,U32.is_lt(code,122923))
def propertiesBelow1925(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1920(code,U32.is_lt(code,122907))
    case False{}: propertiesBelow1924(code,U32.is_lt(code,122918))
def propertiesBelow1926(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1917(code,U32.is_lt(code,122655))
    case False{}: propertiesBelow1925(code,U32.is_lt(code,122915))
def propertiesBelow1927(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1909(code,U32.is_lt(code,121344))
    case False{}: propertiesBelow1926(code,U32.is_lt(code,122888))
def propertiesBelow1928(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1893(code,U32.is_lt(code,120486))
    case False{}: propertiesBelow1927(code,U32.is_lt(code,121504))
def propertiesBelow1929(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1860(code,U32.is_lt(code,118574))
    case False{}: propertiesBelow1928(code,U32.is_lt(code,120714))
def propertiesBelow1930(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1792(code,U32.is_lt(code,73649))
    case False{}: propertiesBelow1929(code,U32.is_lt(code,120071))
def propertiesBelow1931(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1932(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1933(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1931(code,U32.is_lt(code,123023))
    case False{}: propertiesBelow1932(code,U32.is_lt(code,123136))
def propertiesBelow1934(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow1935(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1936(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1934(code,U32.is_lt(code,123184))
    case False{}: propertiesBelow1935(code,U32.is_lt(code,123198))
def propertiesBelow1937(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1933(code,U32.is_lt(code,123024))
    case False{}: propertiesBelow1936(code,U32.is_lt(code,123191))
def propertiesBelow1938(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1939(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1940(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1938(code,U32.is_lt(code,123210))
    case False{}: propertiesBelow1939(code,U32.is_lt(code,123215))
def propertiesBelow1941(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1942(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1943(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1942(code,U32.is_lt(code,123628))
def propertiesBelow1944(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1941(code,U32.is_lt(code,123566))
    case False{}: propertiesBelow1943(code,U32.is_lt(code,123584))
def propertiesBelow1945(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1940(code,U32.is_lt(code,123214))
    case False{}: propertiesBelow1944(code,U32.is_lt(code,123567))
def propertiesBelow1946(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1937(code,U32.is_lt(code,123181))
    case False{}: propertiesBelow1945(code,U32.is_lt(code,123536))
def propertiesBelow1947(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1948(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1949(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1947(code,U32.is_lt(code,123642))
    case False{}: propertiesBelow1948(code,U32.is_lt(code,124140))
def propertiesBelow1950(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: 0
def propertiesBelow1951(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1952(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1950(code,U32.is_lt(code,124154))
    case False{}: propertiesBelow1951(code,U32.is_lt(code,124398))
def propertiesBelow1953(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1949(code,U32.is_lt(code,124112))
    case False{}: propertiesBelow1952(code,U32.is_lt(code,124368))
def propertiesBelow1954(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 10
def propertiesBelow1955(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1956(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1954(code,U32.is_lt(code,124401))
    case False{}: propertiesBelow1955(code,U32.is_lt(code,124608))
def propertiesBelow1957(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1958(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1959(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: propertiesBelow1958(code,U32.is_lt(code,124646))
def propertiesBelow1960(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1957(code,U32.is_lt(code,124640))
    case False{}: propertiesBelow1959(code,U32.is_lt(code,124644))
def propertiesBelow1961(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1956(code,U32.is_lt(code,124411))
    case False{}: propertiesBelow1960(code,U32.is_lt(code,124643))
def propertiesBelow1962(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1953(code,U32.is_lt(code,124144))
    case False{}: propertiesBelow1961(code,U32.is_lt(code,124639))
def propertiesBelow1963(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1946(code,U32.is_lt(code,123200))
    case False{}: propertiesBelow1962(code,U32.is_lt(code,124400))
def propertiesBelow1964(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1965(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1966(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1964(code,U32.is_lt(code,124654))
    case False{}: propertiesBelow1965(code,U32.is_lt(code,124661))
def propertiesBelow1967(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1968(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1969(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1967(code,U32.is_lt(code,124670))
    case False{}: propertiesBelow1968(code,U32.is_lt(code,124896))
def propertiesBelow1970(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1966(code,U32.is_lt(code,124656))
    case False{}: propertiesBelow1969(code,U32.is_lt(code,124672))
def propertiesBelow1971(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1972(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1973(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1971(code,U32.is_lt(code,124904))
    case False{}: propertiesBelow1972(code,U32.is_lt(code,124909))
def propertiesBelow1974(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1975(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1976(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1975(code,U32.is_lt(code,125125))
def propertiesBelow1977(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1974(code,U32.is_lt(code,124912))
    case False{}: propertiesBelow1976(code,U32.is_lt(code,124928))
def propertiesBelow1978(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1973(code,U32.is_lt(code,124908))
    case False{}: propertiesBelow1977(code,U32.is_lt(code,124927))
def propertiesBelow1979(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1970(code,U32.is_lt(code,124662))
    case False{}: propertiesBelow1978(code,U32.is_lt(code,124911))
def propertiesBelow1980(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow1981(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 4
def propertiesBelow1982(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1980(code,U32.is_lt(code,125143))
    case False{}: propertiesBelow1981(code,U32.is_lt(code,125252))
def propertiesBelow1983(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1984(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1985(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 10
    case False{}: propertiesBelow1984(code,U32.is_lt(code,126464))
def propertiesBelow1986(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1983(code,U32.is_lt(code,125260))
    case False{}: propertiesBelow1985(code,U32.is_lt(code,125274))
def propertiesBelow1987(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1982(code,U32.is_lt(code,125184))
    case False{}: propertiesBelow1986(code,U32.is_lt(code,125264))
def propertiesBelow1988(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1989(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1990(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1988(code,U32.is_lt(code,126469))
    case False{}: propertiesBelow1989(code,U32.is_lt(code,126497))
def propertiesBelow1991(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow1992(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow1993(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow1992(code,U32.is_lt(code,126504))
def propertiesBelow1994(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1991(code,U32.is_lt(code,126500))
    case False{}: propertiesBelow1993(code,U32.is_lt(code,126503))
def propertiesBelow1995(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1990(code,U32.is_lt(code,126496))
    case False{}: propertiesBelow1994(code,U32.is_lt(code,126501))
def propertiesBelow1996(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1987(code,U32.is_lt(code,125259))
    case False{}: propertiesBelow1995(code,U32.is_lt(code,126499))
def propertiesBelow1997(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1979(code,U32.is_lt(code,124903))
    case False{}: propertiesBelow1996(code,U32.is_lt(code,126468))
def propertiesBelow1998(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1963(code,U32.is_lt(code,123632))
    case False{}: propertiesBelow1997(code,U32.is_lt(code,125136))
def propertiesBelow1999(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2000(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2001(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1999(code,U32.is_lt(code,126515))
    case False{}: propertiesBelow2000(code,U32.is_lt(code,126520))
def propertiesBelow2002(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2003(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2004(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2002(code,U32.is_lt(code,126522))
    case False{}: propertiesBelow2003(code,U32.is_lt(code,126524))
def propertiesBelow2005(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2001(code,U32.is_lt(code,126516))
    case False{}: propertiesBelow2004(code,U32.is_lt(code,126523))
def propertiesBelow2006(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2007(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2008(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2006(code,U32.is_lt(code,126531))
    case False{}: propertiesBelow2007(code,U32.is_lt(code,126536))
def propertiesBelow2009(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2010(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2011(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow2010(code,U32.is_lt(code,126541))
def propertiesBelow2012(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2009(code,U32.is_lt(code,126538))
    case False{}: propertiesBelow2011(code,U32.is_lt(code,126540))
def propertiesBelow2013(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2008(code,U32.is_lt(code,126535))
    case False{}: propertiesBelow2012(code,U32.is_lt(code,126539))
def propertiesBelow2014(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2005(code,U32.is_lt(code,126521))
    case False{}: propertiesBelow2013(code,U32.is_lt(code,126537))
def propertiesBelow2015(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2016(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2017(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2015(code,U32.is_lt(code,126545))
    case False{}: propertiesBelow2016(code,U32.is_lt(code,126548))
def propertiesBelow2018(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2019(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2020(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2018(code,U32.is_lt(code,126551))
    case False{}: propertiesBelow2019(code,U32.is_lt(code,126553))
def propertiesBelow2021(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2017(code,U32.is_lt(code,126547))
    case False{}: propertiesBelow2020(code,U32.is_lt(code,126552))
def propertiesBelow2022(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2023(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2024(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2022(code,U32.is_lt(code,126555))
    case False{}: propertiesBelow2023(code,U32.is_lt(code,126557))
def propertiesBelow2025(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2026(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2027(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2026(code,U32.is_lt(code,126563))
def propertiesBelow2028(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2025(code,U32.is_lt(code,126559))
    case False{}: propertiesBelow2027(code,U32.is_lt(code,126561))
def propertiesBelow2029(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2024(code,U32.is_lt(code,126556))
    case False{}: propertiesBelow2028(code,U32.is_lt(code,126560))
def propertiesBelow2030(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2021(code,U32.is_lt(code,126549))
    case False{}: propertiesBelow2029(code,U32.is_lt(code,126558))
def propertiesBelow2031(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2014(code,U32.is_lt(code,126530))
    case False{}: propertiesBelow2030(code,U32.is_lt(code,126554))
def propertiesBelow2032(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2033(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2034(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2032(code,U32.is_lt(code,126565))
    case False{}: propertiesBelow2033(code,U32.is_lt(code,126571))
def propertiesBelow2035(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2036(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2037(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2035(code,U32.is_lt(code,126579))
    case False{}: propertiesBelow2036(code,U32.is_lt(code,126584))
def propertiesBelow2038(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2034(code,U32.is_lt(code,126567))
    case False{}: propertiesBelow2037(code,U32.is_lt(code,126580))
def propertiesBelow2039(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2040(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2041(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2039(code,U32.is_lt(code,126589))
    case False{}: propertiesBelow2040(code,U32.is_lt(code,126591))
def propertiesBelow2042(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2043(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2044(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: propertiesBelow2043(code,U32.is_lt(code,126625))
def propertiesBelow2045(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2042(code,U32.is_lt(code,126602))
    case False{}: propertiesBelow2044(code,U32.is_lt(code,126620))
def propertiesBelow2046(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2041(code,U32.is_lt(code,126590))
    case False{}: propertiesBelow2045(code,U32.is_lt(code,126603))
def propertiesBelow2047(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2038(code,U32.is_lt(code,126572))
    case False{}: propertiesBelow2046(code,U32.is_lt(code,126592))
def propertiesBelow2048(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2049(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2050(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2048(code,U32.is_lt(code,126629))
    case False{}: propertiesBelow2049(code,U32.is_lt(code,126635))
def propertiesBelow2051(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2052(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2053(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2052(code,U32.is_lt(code,127024))
def propertiesBelow2054(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2051(code,U32.is_lt(code,126980))
    case False{}: propertiesBelow2053(code,U32.is_lt(code,127020))
def propertiesBelow2055(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2050(code,U32.is_lt(code,126634))
    case False{}: propertiesBelow2054(code,U32.is_lt(code,126981))
def propertiesBelow2056(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2057(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2058(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2056(code,U32.is_lt(code,127136))
    case False{}: propertiesBelow2057(code,U32.is_lt(code,127153))
def propertiesBelow2059(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2060(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2061(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2060(code,U32.is_lt(code,127222))
def propertiesBelow2062(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2059(code,U32.is_lt(code,127169))
    case False{}: propertiesBelow2061(code,U32.is_lt(code,127185))
def propertiesBelow2063(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2058(code,U32.is_lt(code,127151))
    case False{}: propertiesBelow2062(code,U32.is_lt(code,127183))
def propertiesBelow2064(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2055(code,U32.is_lt(code,126652))
    case False{}: propertiesBelow2063(code,U32.is_lt(code,127168))
def propertiesBelow2065(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2047(code,U32.is_lt(code,126585))
    case False{}: propertiesBelow2064(code,U32.is_lt(code,127124))
def propertiesBelow2066(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2031(code,U32.is_lt(code,126544))
    case False{}: propertiesBelow2065(code,U32.is_lt(code,126628))
def propertiesBelow2067(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1998(code,U32.is_lt(code,124647))
    case False{}: propertiesBelow2066(code,U32.is_lt(code,126564))
def propertiesBelow2068(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2069(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 8
def propertiesBelow2070(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2068(code,U32.is_lt(code,127280))
    case False{}: propertiesBelow2069(code,U32.is_lt(code,127312))
def propertiesBelow2071(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 40
def propertiesBelow2072(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 40
def propertiesBelow2073(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2071(code,U32.is_lt(code,127344))
    case False{}: propertiesBelow2072(code,U32.is_lt(code,127358))
def propertiesBelow2074(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2070(code,U32.is_lt(code,127306))
    case False{}: propertiesBelow2073(code,U32.is_lt(code,127346))
def propertiesBelow2075(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 8
    case False{}: 0
def propertiesBelow2076(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2077(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2075(code,U32.is_lt(code,127370))
    case False{}: propertiesBelow2076(code,U32.is_lt(code,127375))
def propertiesBelow2078(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2079(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 18
    case False{}: 0
def propertiesBelow2080(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2079(code,U32.is_lt(code,127488))
def propertiesBelow2081(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2078(code,U32.is_lt(code,127387))
    case False{}: propertiesBelow2080(code,U32.is_lt(code,127462))
def propertiesBelow2082(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2077(code,U32.is_lt(code,127374))
    case False{}: propertiesBelow2081(code,U32.is_lt(code,127406))
def propertiesBelow2083(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2074(code,U32.is_lt(code,127338))
    case False{}: propertiesBelow2082(code,U32.is_lt(code,127377))
def propertiesBelow2084(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2085(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2086(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2084(code,U32.is_lt(code,127504))
    case False{}: propertiesBelow2085(code,U32.is_lt(code,127515))
def propertiesBelow2087(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2088(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2089(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2087(code,U32.is_lt(code,127536))
    case False{}: propertiesBelow2088(code,U32.is_lt(code,127547))
def propertiesBelow2090(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2086(code,U32.is_lt(code,127514))
    case False{}: propertiesBelow2089(code,U32.is_lt(code,127538))
def propertiesBelow2091(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2092(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2093(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2091(code,U32.is_lt(code,127552))
    case False{}: propertiesBelow2092(code,U32.is_lt(code,127584))
def propertiesBelow2094(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2095(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2096(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2095(code,U32.is_lt(code,127894))
def propertiesBelow2097(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2094(code,U32.is_lt(code,127778))
    case False{}: propertiesBelow2096(code,U32.is_lt(code,127892))
def propertiesBelow2098(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2093(code,U32.is_lt(code,127561))
    case False{}: propertiesBelow2097(code,U32.is_lt(code,127780))
def propertiesBelow2099(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2090(code,U32.is_lt(code,127535))
    case False{}: propertiesBelow2098(code,U32.is_lt(code,127590))
def propertiesBelow2100(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2083(code,U32.is_lt(code,127360))
    case False{}: propertiesBelow2099(code,U32.is_lt(code,127548))
def propertiesBelow2101(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2102(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2103(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2101(code,U32.is_lt(code,127897))
    case False{}: propertiesBelow2102(code,U32.is_lt(code,127902))
def propertiesBelow2104(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2105(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2106(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2104(code,U32.is_lt(code,127987))
    case False{}: propertiesBelow2105(code,U32.is_lt(code,127991))
def propertiesBelow2107(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2103(code,U32.is_lt(code,127900))
    case False{}: propertiesBelow2106(code,U32.is_lt(code,127990))
def propertiesBelow2108(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 32
def propertiesBelow2109(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2110(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2108(code,U32.is_lt(code,128000))
    case False{}: propertiesBelow2109(code,U32.is_lt(code,128255))
def propertiesBelow2111(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2112(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2113(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2112(code,U32.is_lt(code,128360))
def propertiesBelow2114(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2111(code,U32.is_lt(code,128329))
    case False{}: propertiesBelow2113(code,U32.is_lt(code,128336))
def propertiesBelow2115(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2110(code,U32.is_lt(code,128254))
    case False{}: propertiesBelow2114(code,U32.is_lt(code,128335))
def propertiesBelow2116(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2107(code,U32.is_lt(code,127985))
    case False{}: propertiesBelow2115(code,U32.is_lt(code,128318))
def propertiesBelow2117(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2118(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2119(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2117(code,U32.is_lt(code,128369))
    case False{}: propertiesBelow2118(code,U32.is_lt(code,128379))
def propertiesBelow2120(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2121(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2122(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2121(code,U32.is_lt(code,128400))
def propertiesBelow2123(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2120(code,U32.is_lt(code,128392))
    case False{}: propertiesBelow2122(code,U32.is_lt(code,128398))
def propertiesBelow2124(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2119(code,U32.is_lt(code,128371))
    case False{}: propertiesBelow2123(code,U32.is_lt(code,128394))
def propertiesBelow2125(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2126(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2127(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2125(code,U32.is_lt(code,128405))
    case False{}: propertiesBelow2126(code,U32.is_lt(code,128420))
def propertiesBelow2128(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2129(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2130(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2129(code,U32.is_lt(code,128435))
def propertiesBelow2131(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2128(code,U32.is_lt(code,128424))
    case False{}: propertiesBelow2130(code,U32.is_lt(code,128433))
def propertiesBelow2132(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2127(code,U32.is_lt(code,128407))
    case False{}: propertiesBelow2131(code,U32.is_lt(code,128425))
def propertiesBelow2133(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2124(code,U32.is_lt(code,128391))
    case False{}: propertiesBelow2132(code,U32.is_lt(code,128422))
def propertiesBelow2134(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2116(code,U32.is_lt(code,127995))
    case False{}: propertiesBelow2133(code,U32.is_lt(code,128401))
def propertiesBelow2135(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2100(code,U32.is_lt(code,127489))
    case False{}: propertiesBelow2134(code,U32.is_lt(code,128367))
def propertiesBelow2136(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2137(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2138(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2136(code,U32.is_lt(code,128445))
    case False{}: propertiesBelow2137(code,U32.is_lt(code,128453))
def propertiesBelow2139(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2140(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2141(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2139(code,U32.is_lt(code,128468))
    case False{}: propertiesBelow2140(code,U32.is_lt(code,128479))
def propertiesBelow2142(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2138(code,U32.is_lt(code,128450))
    case False{}: propertiesBelow2141(code,U32.is_lt(code,128476))
def propertiesBelow2143(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2144(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2145(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2143(code,U32.is_lt(code,128482))
    case False{}: propertiesBelow2144(code,U32.is_lt(code,128484))
def propertiesBelow2146(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2147(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2148(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2147(code,U32.is_lt(code,128499))
def propertiesBelow2149(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2146(code,U32.is_lt(code,128489))
    case False{}: propertiesBelow2148(code,U32.is_lt(code,128496))
def propertiesBelow2150(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2145(code,U32.is_lt(code,128483))
    case False{}: propertiesBelow2149(code,U32.is_lt(code,128495))
def propertiesBelow2151(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2142(code,U32.is_lt(code,128465))
    case False{}: propertiesBelow2150(code,U32.is_lt(code,128488))
def propertiesBelow2152(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2153(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2154(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2152(code,U32.is_lt(code,128506))
    case False{}: propertiesBelow2153(code,U32.is_lt(code,128640))
def propertiesBelow2155(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2156(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2157(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2156(code,U32.is_lt(code,128742))
def propertiesBelow2158(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2155(code,U32.is_lt(code,128715))
    case False{}: propertiesBelow2157(code,U32.is_lt(code,128725))
def propertiesBelow2159(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2154(code,U32.is_lt(code,128592))
    case False{}: propertiesBelow2158(code,U32.is_lt(code,128723))
def propertiesBelow2160(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2161(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2162(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2160(code,U32.is_lt(code,128746))
    case False{}: propertiesBelow2161(code,U32.is_lt(code,128753))
def propertiesBelow2163(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2164(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2165(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2164(code,U32.is_lt(code,129036))
def propertiesBelow2166(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2163(code,U32.is_lt(code,128768))
    case False{}: propertiesBelow2165(code,U32.is_lt(code,129024))
def propertiesBelow2167(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2162(code,U32.is_lt(code,128747))
    case False{}: propertiesBelow2166(code,U32.is_lt(code,128986))
def propertiesBelow2168(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2159(code,U32.is_lt(code,128710))
    case False{}: propertiesBelow2167(code,U32.is_lt(code,128755))
def propertiesBelow2169(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2151(code,U32.is_lt(code,128481))
    case False{}: propertiesBelow2168(code,U32.is_lt(code,128745))
def propertiesBelow2170(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2171(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2172(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2170(code,U32.is_lt(code,129096))
    case False{}: propertiesBelow2171(code,U32.is_lt(code,129114))
def propertiesBelow2173(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2174(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2175(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2173(code,U32.is_lt(code,129160))
    case False{}: propertiesBelow2174(code,U32.is_lt(code,129198))
def propertiesBelow2176(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2172(code,U32.is_lt(code,129104))
    case False{}: propertiesBelow2175(code,U32.is_lt(code,129168))
def propertiesBelow2177(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2178(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2179(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2177(code,U32.is_lt(code,129212))
    case False{}: propertiesBelow2178(code,U32.is_lt(code,129218))
def propertiesBelow2180(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2181(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2182(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2181(code,U32.is_lt(code,129339))
def propertiesBelow2183(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2180(code,U32.is_lt(code,129241))
    case False{}: propertiesBelow2182(code,U32.is_lt(code,129292))
def propertiesBelow2184(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2179(code,U32.is_lt(code,129216))
    case False{}: propertiesBelow2183(code,U32.is_lt(code,129280))
def propertiesBelow2185(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2176(code,U32.is_lt(code,129120))
    case False{}: propertiesBelow2184(code,U32.is_lt(code,129232))
def propertiesBelow2186(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2187(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2188(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2186(code,U32.is_lt(code,129350))
    case False{}: propertiesBelow2187(code,U32.is_lt(code,129536))
def propertiesBelow2189(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: 0
def propertiesBelow2190(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 10
def propertiesBelow2191(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 32
    case False{}: propertiesBelow2190(code,U32.is_lt(code,130032))
def propertiesBelow2192(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2189(code,U32.is_lt(code,129632))
    case False{}: propertiesBelow2191(code,U32.is_lt(code,129792))
def propertiesBelow2193(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2188(code,U32.is_lt(code,129351))
    case False{}: propertiesBelow2192(code,U32.is_lt(code,129646))
def propertiesBelow2194(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 32
def propertiesBelow2195(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 5
def propertiesBelow2196(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2194(code,U32.is_lt(code,130048))
    case False{}: propertiesBelow2195(code,U32.is_lt(code,917505))
def propertiesBelow2197(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: 4
def propertiesBelow2198(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 4
    case False{}: 0
def propertiesBelow2199(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: 0
    case False{}: propertiesBelow2198(code,U32.is_lt(code,918000))
def propertiesBelow2200(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2197(code,U32.is_lt(code,917536))
    case False{}: propertiesBelow2199(code,U32.is_lt(code,917760))
def propertiesBelow2201(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2196(code,U32.is_lt(code,131070))
    case False{}: propertiesBelow2200(code,U32.is_lt(code,917632))
def propertiesBelow2202(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2193(code,U32.is_lt(code,129624))
    case False{}: propertiesBelow2201(code,U32.is_lt(code,917506))
def propertiesBelow2203(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2185(code,U32.is_lt(code,129200))
    case False{}: propertiesBelow2202(code,U32.is_lt(code,130042))
def propertiesBelow2204(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2169(code,U32.is_lt(code,128500))
    case False{}: propertiesBelow2203(code,U32.is_lt(code,129340))
def propertiesBelow2205(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2135(code,U32.is_lt(code,127896))
    case False{}: propertiesBelow2204(code,U32.is_lt(code,129040))
def propertiesBelow2206(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow2067(code,U32.is_lt(code,126505))
    case False{}: propertiesBelow2205(code,U32.is_lt(code,128444))
def propertiesBelow2207(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1930(code,U32.is_lt(code,94179))
    case False{}: propertiesBelow2206(code,U32.is_lt(code,127232))
def propertiesBelow2208(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1655(code,U32.is_lt(code,68736))
    case False{}: propertiesBelow2207(code,U32.is_lt(code,122990))
def propertiesBelow2209(+code: U32,below: Bool) -> U32:
  match below:
    case True{}: propertiesBelow1103(code,U32.is_lt(code,4752))
    case False{}: propertiesBelow2208(code,U32.is_lt(code,72698))

def properties(+code: U32) -> U32:
  propertiesBelow2209(code,U32.is_lt(code,43587))
