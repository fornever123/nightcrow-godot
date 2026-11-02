// 「雨夜河岸街」钟楼广场右半边（r1 第四版）的明暗草图：GPT 照着画成图。
// 画面 = 世界 x −150 ~ 2560、y −700 ~ 826（1672×941，和左半边同一比例）。SVG viewBox 直接用世界坐标。
// 背景（天空 + 远景）和最左边的钟楼一窄条是成图（public/，由 prep.py 生成），中间的楼是这里画的草图。
// 平台、路灯来自 public/layout.json（= assets/data/rain_street_layout.json 的副本）。
// 设计：四栋窄楼宽窄高低错开 —— 窄高的当铺（阶梯山墙）/ 两层的船具行（砖墙平顶）/ 最高最暗的警署（截顶陡坡、尖拱窗、蓝灯）/
// 折线屋顶住宅；焦点是钟楼和当铺之间亮雾前的维多利亚铸铁码头吊车（吊臂能站）。阳台各在自己的楼上，三层平台高低成锯齿。
import React, { useEffect, useState } from "react";
import { AbsoluteFill, Img, continueRender, delayRender, staticFile } from "remotion";

export type Props = { readonly showLines: boolean; readonly showOpenings: boolean };

// 门窗开关：showOpenings=false 时草图只给体量、屋顶轮廓、阳台和能站的面、明暗、灯和招牌，门窗全部交给提示词描述（测试版）
export const OpeningsCtx = React.createContext(true);
export const Op: React.FC<{ children: React.ReactNode }> = ({ children }) => (React.useContext(OpeningsCtx) ? <>{children}</> : null);

export type Plat = [number, number, number, string];
export type Lamp = [number, number, string, number?];
export type Section = { platforms: Plat[]; blocks: Plat[]; lamps: Lamp[] };
export type Pt = [number, number];

const X0 = -150;
const X1 = 2560;
const Y0 = -700;
const VW = X1 - X0;
const VH = (VW * 941) / 1672;
const FLOOR = 580;
const ART_X = 263; // 左半边成图的右边缘：这以左是成图

export const pts = (a: Pt[]) => a.map(([x, y]) => `${x},${y}`).join(" ");
export const IRON = "#16171e";
export const GLASS = "#0c0f16";
export const WARM = "#e8c884";
export const DIM = "#b0926a";
export const TRIM = "#7a8294";
export const RIM = "#b6c0d4";
export const WOOD = "#2a2422";

// ---------------------------------------------------------------- 窗、门的形状
export const archPath = (cx: number, bottom: number, w: number, h: number) => {
  const hh = Math.max(h, 0.866 * w + 4);
  const ys = bottom - hh + 0.866 * w;
  const ay = ys - 0.866 * w;
  return `M ${cx - w / 2} ${bottom} L ${cx - w / 2} ${ys} A ${w} ${w} 0 0 1 ${cx} ${ay} A ${w} ${w} 0 0 1 ${cx + w / 2} ${ys} L ${cx + w / 2} ${bottom} Z`;
};
export const segPath = (cx: number, bottom: number, w: number, h: number) => {
  const top = bottom - h;
  const rise = w * 0.16;
  return `M ${cx - w / 2} ${bottom} L ${cx - w / 2} ${top + rise} Q ${cx} ${top - rise} ${cx + w / 2} ${top + rise} L ${cx + w / 2} ${bottom} Z`;
};
export const roundPath = (cx: number, bottom: number, w: number, h: number) => {
  const top = bottom - h;
  return `M ${cx - w / 2} ${bottom} L ${cx - w / 2} ${top + w / 2} A ${w / 2} ${w / 2} 0 0 1 ${cx + w / 2} ${top + w / 2} L ${cx + w / 2} ${bottom} Z`;
};

/** 尖拱窗 + 浅石窗套（窗套跟着尖拱走） */
const LancetRaw: React.FC<{ cx: number; bottom: number; w: number; h: number; fill?: string; surround?: string }> = ({ cx, bottom, w, h, fill = GLASS, surround = TRIM }) => (
  <g>
    <path d={archPath(cx, bottom + 4, w + 16, h + 10)} fill={surround} />
    <path d={archPath(cx, bottom, w, h)} fill={fill} />
    <line x1={cx} y1={bottom} x2={cx} y2={bottom - h + w * 0.9} stroke={fill === GLASS ? "#283040" : "#8a6a40"} strokeWidth={2.5} />
    {fill === GLASS && <line x1={cx + w * 0.3} y1={bottom - h + w * 0.9} x2={cx + w * 0.3} y2={bottom - 8} stroke="#3a4660" strokeWidth={2.5} />}
  </g>
);

/** 弧头窗（货栈 / 当铺 / 船具行），砖拱窗头 + 窗台 */
const SegRaw: React.FC<{ cx: number; bottom: number; w: number; h: number; fill?: string }> = ({ cx, bottom, w, h, fill = GLASS }) => (
  <g>
    <path d={segPath(cx, bottom + 6, w + 16, h + 16)} fill="#5a5862" />
    <path d={segPath(cx, bottom, w, h)} fill={fill} />
    <line x1={cx} y1={bottom - h} x2={cx} y2={bottom} stroke={fill === GLASS ? "#283040" : "#8a6a40"} strokeWidth={2.5} />
    <line x1={cx - w / 2} y1={bottom - h * 0.5} x2={cx + w / 2} y2={bottom - h * 0.5} stroke={fill === GLASS ? "#283040" : "#8a6a40"} strokeWidth={2.5} />
    <rect x={cx - w / 2 - 10} y={bottom + 2} width={w + 20} height={6} fill="#6a7080" />
  </g>
);

/** 方窗（住宅）：上下推拉窗格 */
const SashRaw: React.FC<{ cx: number; bottom: number; w: number; h: number; fill?: string }> = ({ cx, bottom, w, h, fill = GLASS }) => (
  <g>
    <rect x={cx - w / 2 - 8} y={bottom - h - 8} width={w + 16} height={h + 14} fill="#6a7284" />
    <rect x={cx - w / 2} y={bottom - h} width={w} height={h} fill={fill} />
    <line x1={cx} y1={bottom - h} x2={cx} y2={bottom} stroke={fill === GLASS ? "#283040" : "#8a6a40"} strokeWidth={2.5} />
    <line x1={cx - w / 2} y1={bottom - h * 0.5} x2={cx + w / 2} y2={bottom - h * 0.5} stroke={fill === GLASS ? "#283040" : "#8a6a40"} strokeWidth={3} />
  </g>
);

export const Lancet: typeof LancetRaw = (p) => <Op><LancetRaw {...p} /></Op>;
export const Seg: typeof SegRaw = (p) => <Op><SegRaw {...p} /></Op>;
export const Sash: typeof SashRaw = (p) => <Op><SashRaw {...p} /></Op>;

/** 楼的右边缘：月光亮边 */
export const LitEdge: React.FC<{ x: number; y0: number; y1: number; w?: number }> = ({ x, y0, y1, w = 14 }) => (
  <rect x={x - w} y={y0} width={w} height={y1 - y0} fill="url(#litEdge)" />
);
export const Pilaster: React.FC<{ x: number; y0: number; y1: number; w?: number }> = ({ x, y0, y1, w = 16 }) => (
  <g>
    <rect x={x} y={y0} width={w} height={y1 - y0} fill="url(#pilaster)" />
    <line x1={x + w} y1={y0} x2={x + w} y2={y1} stroke="#8c96ac" strokeWidth={2} />
  </g>
);
export const Band: React.FC<{ x0: number; x1: number; y: number; h?: number }> = ({ x0, x1, y, h = 12 }) => (
  <g>
    <rect x={x0} y={y} width={x1 - x0} height={h} fill="#1e232e" />
    <line x1={x0} y1={y} x2={x1} y2={y} stroke="#606878" strokeWidth={2} />
  </g>
);
export const Stack: React.FC<{ x0: number; x1: number; top: number; base: number; pots?: number }> = ({ x0, x1, top, base, pots = 2 }) => {
  const w = (x1 - x0) / pots;
  return (
    <g>
      <rect x={x0} y={top} width={x1 - x0} height={base - top} fill="#1e2129" />
      {Array.from({ length: pots }, (_, i) => (
        <rect key={i} x={x0 + w * i + w * 0.22} y={top - 30} width={w * 0.56} height={30} fill="#1e2129" />
      ))}
      <rect x={x0 - 6} y={top} width={x1 - x0 + 12} height={10} fill="#2c313c" />
      <line x1={x1} y1={top} x2={x1} y2={base} stroke="#a0acc4" strokeWidth={3} />
    </g>
  );
};
export const Plinth: React.FC<{ x0: number; x1: number; top?: number; col?: string }> = ({ x0, x1, top = 470, col = "#2c313e" }) => (
  <g>
    <rect x={x0} y={top} width={x1 - x0} height={FLOOR - top} fill={col} />
    {Array.from({ length: Math.floor((FLOOR - top) / 28) }, (_, i) => (
      <line key={i} x1={x0} y1={top + 14 + i * 28} x2={x1} y2={top + 14 + i * 28} stroke="#1a1e28" strokeWidth={2} />
    ))}
    <Band x0={x0} x1={x1} y={top - 14} h={14} />
  </g>
);
export const Gargoyle: React.FC<{ x: number; y: number; s: number }> = ({ x, y, s }) => (
  <g>
    <polygon points={pts([[x, y], [x + s * 40, y + 4], [x + s * 70, y - 12], [x + s * 84, y], [x + s * 60, y + 16], [x + s * 36, y + 24], [x, y + 30]])} fill="#2c303c" />
    <polygon points={pts([[x + s * 40, y + 4], [x + s * 48, y - 30], [x + s * 64, y - 6]])} fill="#2c303c" />
    <polyline points={pts([[x + s * 84, y], [x + s * 70, y - 12], [x + s * 40, y + 4]])} stroke="#96a0b6" strokeWidth={2} fill="none" />
  </g>
);
export const bez = (p0: Pt, p1: Pt, p2: Pt) => `M ${p0[0]} ${p0[1]} Q ${p1[0]} ${p1[1]} ${p2[0]} ${p2[1]}`;

// ---------------------------------------------------------------- 焦点：维多利亚铸铁码头吊车（石台 [420,650] 上）
const Crane: React.FC = () => (
  <g>
    {/* 带凹槽的铸铁圆柱 + 喇叭形柱脚 */}
    <polygon points={pts([[560, 470], [650, 470], [632, 432], [630, 160], [580, 160], [578, 432]])} fill="#111218" />
    {[592, 605, 618].map((x) => (
      <line key={x} x1={x} y1={170} x2={x} y2={425} stroke="#2a2e3a" strokeWidth={3} />
    ))}
    <line x1={631} y1={160} x2={633} y2={432} stroke="#7a86a0" strokeWidth={2.5} />
    <rect x={572} y={146} width={66} height={16} fill="#111218" />
    {/* 柱顶短王柱 + 尖饰 + 滑轮 */}
    <polygon points={pts([[590, 146], [620, 146], [612, -60], [598, -60]])} fill="#111218" />
    <polygon points={pts([[598, -60], [612, -60], [605, -104]])} fill="#111218" />
    <circle cx={605} cy={-40} r={12} fill="none" stroke="#111218" strokeWidth={5} />
    {/* 铆接铁板梁吊臂（顶面 140 能站）：竖向加劲肋 + 一排铆钉 */}
    <rect x={380} y={140} width={300} height={40} fill="#14151c" />
    {Array.from({ length: 9 }, (_, i) => (
      <line key={i} x1={400 + i * 32} y1={142} x2={400 + i * 32} y2={178} stroke="#2a2f3c" strokeWidth={3} />
    ))}
    {Array.from({ length: 28 }, (_, i) => (
      <rect key={i} x={386 + i * 10.4} y={146} width={3} height={3} fill="#3a4152" />
    ))}
    <line x1={380} y1={180} x2={680} y2={180} stroke="#2a2f3c" strokeWidth={3} />
    {/* 弧形铸铁斜撑、两根拉杆、配重箱、小车 + 长铁索 + 吊钩、绞盘 */}
    <path d={bez([600, 400], [420, 380], [395, 182])} stroke="#111218" strokeWidth={9} fill="none" />
    <path d={bez([600, 400], [420, 380], [395, 182])} stroke="#4a5268" strokeWidth={2} fill="none" transform="translate(4,-2)" />
    <line x1={605} y1={-50} x2={386} y2={140} stroke="#111218" strokeWidth={5} />
    <line x1={605} y1={-50} x2={672} y2={140} stroke="#111218" strokeWidth={5} />
    <rect x={640} y={180} width={40} height={60} fill="#14151c" />
    <rect x={420} y={180} width={26} height={16} fill="#111218" />
    <line x1={433} y1={196} x2={433} y2={420} stroke="#111218" strokeWidth={3} />
    <path d="M 433 420 q -14 8 -6 22 q 10 8 18 -4" stroke="#111218" strokeWidth={5} fill="none" />
    <rect x={508} y={404} width={44} height={40} rx={4} fill="#14151c" />
    <circle cx={530} cy={412} r={30} fill="none" stroke="#111218" strokeWidth={7} />
    <circle cx={566} cy={440} r={14} fill="none" stroke="#111218" strokeWidth={5} />
    <line x1={500} y1={470} x2={530} y2={412} stroke="#111218" strokeWidth={5} />
    <line x1={560} y1={470} x2={530} y2={412} stroke="#111218" strokeWidth={5} />
    <line x1={672} y1={140} x2={605} y2={-50} stroke="#8a96b0" strokeWidth={1.5} />
  </g>
);

// ---------------------------------------------------------------- A 当铺（720–1000，窄高，轴线 805 / 915）：阶梯山墙
const Pawnshop: React.FC = () => {
  const half: Pt[] = [];
  let y = -300;
  half.push([0, -300]);
  for (let i = 0; i < 5; i++) {
    half.push([i * 28, y - 44]);
    half.push([i * 28 + 28, y - 44]);
    y -= 44;
  }
  const gab: Pt[] = [...half.map(([dx, yy]) => [720 + dx, yy] as Pt), ...[...half].reverse().map(([dx, yy]) => [1000 - dx, yy] as Pt)];
  return (
    <g>
      <rect x={720} y={-300} width={280} height={FLOOR + 300} fill="url(#pawnWall)" />
      <polygon points={pts(gab)} fill="url(#pawnGable)" />
      {half.slice(1).filter((_, i) => i % 2 === 1).map(([dx, yy], i) => (
        <g key={i}>
          <polygon points={pts([[720 + dx - 4, yy], [720 + dx - 14, yy], [720 + dx - 9, yy - 18]])} fill="#2a2e3a" />
          <polygon points={pts([[1000 - dx + 4, yy], [1000 - dx + 14, yy], [1000 - dx + 9, yy - 18]])} fill="#2a2e3a" />
        </g>
      ))}
      <polyline points={pts([...half].reverse().map(([dx, yy]) => [1000 - dx, yy] as Pt))} stroke={RIM} strokeWidth={3} fill="none" />
      <Stack x0={735} x1={772} top={-500} base={-346} />
      <Pilaster x={720} y0={-300} y1={470} />
      <Pilaster x={984} y0={-300} y1={470} />
      <LitEdge x={1000} y0={-300} y1={300} />
      <Band x0={720} x1={1000} y={-300} h={10} />
      <Plinth x0={720} x1={1000} />
      <Lancet cx={860} bottom={-370} w={28} h={80} />
      {[805, 915].map((ax) => (
        <g key={ax}>
          <Seg cx={ax} bottom={-200} w={40} h={70} />
          <Seg cx={ax} bottom={10} w={42} h={170} />
          <Seg cx={ax} bottom={290} w={46} h={220} />
        </g>
      ))}
      {/* 一层：深色木门脸 + 分格橱窗暗暖光 + 木门 */}
      <rect x={728} y={374} width={264} height={FLOOR - 374} fill="#1c1a1e" />
      <rect x={736} y={382} width={248} height={26} fill="#141216" stroke="#605a58" strokeWidth={2} />
      <Op>
      <rect x={738} y={416} width={134} height={152} fill="#201e22" />
      <rect x={745} y={424} width={120} height={136} fill="url(#warmWin)" />
      {[775, 805, 835].map((gx) => (
        <line key={gx} x1={gx} y1={424} x2={gx} y2={560} stroke="#201e22" strokeWidth={3} />
      ))}
      <line x1={745} y1={470} x2={865} y2={470} stroke="#201e22" strokeWidth={3} />
      <rect x={888} y={424} width={54} height={FLOOR - 424} fill={WOOD} />
      <line x1={915} y1={424} x2={915} y2={FLOOR} stroke="#141010" strokeWidth={2} />
      </Op>
      {/* 三颗挂球：店招高度从左墙角伸出，压在亮雾上 */}
      <line x1={720} y1={380} x2={654} y2={380} stroke={IRON} strokeWidth={4} />
      <line x1={720} y1={410} x2={676} y2={380} stroke={IRON} strokeWidth={3} />
      {[[675, 410], [662, 434], [688, 434]].map(([cx, cy]) => (
        <circle key={cx} cx={cx} cy={cy} r={12} fill="#7a6640" />
      ))}
      {/* 二层壁灯 */}
      <rect x={850} y={160} width={20} height={36} fill={WARM} />
      <line x1={840} y1={160} x2={860} y2={150} stroke={IRON} strokeWidth={3} />
    </g>
  );
};

// ---------------------------------------------------------------- B 船具行（1000–1450，两层，砖墙平顶 120）
const Chandlery: React.FC = () => (
  <g>
    {/* 船具行矮下去露出的：雾里的后排坡屋顶（比船具行墙亮、边缘虚） */}
    <polygon points={pts([[990, 130], [990, -30], [1060, -100], [1130, -30], [1160, -30], [1230, -110], [1300, -30], [1330, -40], [1400, -100], [1460, -30], [1460, 130]])} fill="#2e3646" filter="url(#b2)" />
    {[1086, 1250, 1376].map((x) => (
      <rect key={x} x={x} y={-150} width={22} height={70} fill="#2e3646" filter="url(#b2)" />
    ))}
    <rect x={1000} y={120} width={450} height={FLOOR - 120} fill="url(#brickWall)" />
    <Band x0={1000} x1={1450} y={120} h={10} />
    <LitEdge x={1450} y0={120} y1={300} />
    <Stack x0={1390} x1={1426} top={-40} base={100} />
    <Seg cx={1110} bottom={290} w={52} h={130} />
    <Seg cx={1340} bottom={290} w={52} h={130} />
    {/* 中轴：二层卸货门 + 门上方挑出的吊货梁、滑轮、绳 */}
    <Op>
    <rect x={1195} y={150} width={60} height={150} fill={WOOD} />
    <line x1={1225} y1={150} x2={1225} y2={300} stroke="#141010" strokeWidth={2} />
    <line x1={1195} y1={225} x2={1255} y2={225} stroke="#141010" strokeWidth={2} />
    <line x1={1195} y1={286} x2={1255} y2={286} stroke={IRON} strokeWidth={3} />
    </Op>
    <line x1={1218} y1={110} x2={1292} y2={110} stroke={IRON} strokeWidth={7} />
    <line x1={1225} y1={130} x2={1225} y2={104} stroke={IRON} strokeWidth={5} />
    <circle cx={1288} cy={124} r={10} fill={IRON} />
    <line x1={1288} y1={134} x2={1288} y2={330} stroke={IRON} strokeWidth={2} />
    {/* 1110：砖砌弧头车门，半开，门缝透暗暖光 */}
    <Op>
    <path d={segPath(1110, FLOOR, 140, 196)} fill="#201a1a" />
    <path d={segPath(1110, FLOOR, 152, 206)} fill="none" stroke="#3a3434" strokeWidth={8} />
    {Array.from({ length: 6 }, (_, i) => (
      <line key={i} x1={1048 + i * 20} y1={398} x2={1048 + i * 20} y2={FLOOR} stroke="#141010" strokeWidth={2} />
    ))}
    <rect x={1108} y={396} width={14} height={FLOOR - 396} fill={DIM} opacity={0.85} />
    </Op>
    {/* 1340：维多利亚店面（暗暖光，里面是成卷缆绳和马灯的剪影） */}
    <rect x={1262} y={372} width={180} height={FLOOR - 372} fill="#1a1a1e" />
    <rect x={1270} y={378} width={164} height={24} fill="#121216" stroke="#5c5c62" strokeWidth={2} />
    <Op>
    <rect x={1284} y={420} width={112} height={136} fill="url(#warmWin)" />
    <line x1={1340} y1={420} x2={1340} y2={556} stroke="#1a1a1e" strokeWidth={3} />
    <circle cx={1312} cy={516} r={16} fill="none" stroke="#2a2220" strokeWidth={5} />
    <rect x={1362} y={472} width={16} height={22} fill="none" stroke="#2a2220" strokeWidth={3} />
    <rect x={1406} y={424} width={30} height={FLOOR - 424} fill={WOOD} />
    </Op>
    {/* 门前一组缆绳卷 + 两只木桶（右半边第二处、也是最后一处杂物） */}
    <ellipse cx={1205} cy={566} rx={22} ry={14} fill="#2c2622" />
    <ellipse cx={1205} cy={566} rx={10} ry={6} fill="#1a1614" />
    <rect x={1228} y={536} width={26} height={44} rx={6} fill="#2e2824" />
    <rect x={1252} y={540} width={24} height={40} rx={6} fill="#2a2420" />
    {/* 楼右角：铁锚招牌（约 90 高）+ 一对船灯 */}
    <line x1={1450} y1={318} x2={1520} y2={318} stroke={IRON} strokeWidth={5} />
    <line x1={1450} y1={350} x2={1500} y2={318} stroke={IRON} strokeWidth={3} />
    <line x1={1500} y1={318} x2={1500} y2={330} stroke={IRON} strokeWidth={2} />
    <path d="M 1500 330 L 1500 412 M 1482 344 L 1518 344 M 1474 392 Q 1500 428 1526 392" stroke={IRON} strokeWidth={6} fill="none" />
    <circle cx={1500} cy={330} r={6} fill="none" stroke={IRON} strokeWidth={3} />
    {[1462, 1536].map((x) => (
      <g key={x}>
        <line x1={x} y1={318} x2={x} y2={336} stroke={IRON} strokeWidth={2} />
        <rect x={x - 6} y={336} width={12} height={16} fill={DIM} />
      </g>
    ))}
  </g>
);

// ---------------------------------------------------------------- 巷子：深处的暗后排楼 + 半开的铸铁拱门
const Alley: React.FC = () => (
  <g>
    <polygon points={pts([[1470, FLOOR], [1470, -40], [1535, -120], [1600, -40], [1600, FLOOR]])} fill="url(#alleyBack)" filter="url(#b2)" />
    {Array.from({ length: 10 }, (_, i) => (
      <line key={i} x1={1462 + i * 16} y1={410} x2={1462 + i * 16} y2={FLOOR} stroke={IRON} strokeWidth={2} />
    ))}
    <line x1={1458} y1={414} x2={1614} y2={414} stroke={IRON} strokeWidth={3} />
    <path d="M 1458 414 A 78 70 0 0 1 1614 414" stroke={IRON} strokeWidth={3} fill="none" />
    {/* 巷口：麻袋 + 倒扣的木桶 */}
    <ellipse cx={1486} cy={566} rx={24} ry={16} fill="#2a2622" />
    <ellipse cx={1512} cy={560} rx={22} ry={22} fill="#2a2622" />
    <rect x={1576} y={536} width={30} height={44} rx={7} fill="#2a2622" />
    {/* 天桥边的小壁灯 */}
    <rect x={1530} y={-10} width={20} height={36} fill={WARM} />
  </g>
);

// ---------------------------------------------------------------- C 警署（1620–2000，最高最暗，轴线 1715 / 1905）
const Police: React.FC = () => {
  const roof: Pt[] = [[1632, -255], [1660, -300], [1760, -600], [1860, -600], [1960, -300], [1988, -255]];
  return (
    <g>
      <rect x={1620} y={-255} width={380} height={FLOOR + 255} fill="url(#policeWall)" />
      <polygon points={pts(roof)} fill="url(#policeRoof)" />
      <polyline points={pts(roof.slice(3))} stroke={RIM} strokeWidth={4} fill="none" />
      {/* 平顶上一圈带尖刺的铁花栏 */}
      <line x1={1760} y1={-622} x2={1860} y2={-622} stroke={IRON} strokeWidth={3} />
      {Array.from({ length: 9 }, (_, i) => (
        <polygon key={i} points={pts([[1762 + i * 12, -600], [1766 + i * 12, -600], [1764 + i * 12, -650]])} fill={IRON} />
      ))}
      {/* 两扇尖山花老虎窗 */}
      {[1715, 1905].map((ax) => (
        <g key={ax}>
          <rect x={ax - 30} y={-470} width={60} height={90} fill="#1e212a" />
          <polygon points={pts([[ax - 38, -470], [ax, -520], [ax + 38, -470]])} fill="#2a2e3a" />
          <Lancet cx={ax} bottom={-392} w={28} h={66} />
        </g>
      ))}
      {/* 左壁柱加宽（桥头）+ 右壁柱，贯通到护墙 */}
      <rect x={1620} y={-255} width={40} height={725} fill="url(#policePier)" />
      <rect x={1970} y={-255} width={30} height={725} fill="url(#policePier)" />
      {/* 桥头铁栏侧门（天桥 120 接在这里） */}
      <Op>
      <rect x={1626} y={10} width={30} height={110} fill={GLASS} />
      {[1632, 1641, 1650].map((x) => (
        <line key={x} x1={x} y1={10} x2={x} y2={120} stroke="#4a5266" strokeWidth={2} />
      ))}
      </Op>
      <LitEdge x={2000} y0={-255} y1={300} />
      {/* 护墙正中：不写字的徽章浮雕 */}
      <path d="M 1790 -300 L 1830 -300 L 1830 -276 Q 1810 -256 1790 -276 Z" fill="#3a404e" stroke="#5a6274" strokeWidth={2} />
      {/* 窗：三层一对尖窗（右窗暗暖光），二层一对高尖窗，浅石窗套 */}
      <Lancet cx={1715} bottom={-30} w={46} h={190} surround="#5a6276" />
      <Lancet cx={1905} bottom={-30} w={46} h={190} fill={DIM} surround="#5a6276" />
      <Lancet cx={1715} bottom={310} w={50} h={230} surround="#5a6276" />
      <Lancet cx={1905} bottom={310} w={50} h={230} surround="#5a6276" />
      {/* 一层：横缝粗石基座 + 铁栏方窗（暗暖值班室光）+ 圆拱双开门、粗石拱券 + 方玻璃蓝色警灯 */}
      <rect x={1620} y={390} width={380} height={FLOOR - 390} fill="#2e323c" />
      {Array.from({ length: 7 }, (_, i) => (
        <line key={i} x1={1620} y1={404 + i * 26} x2={2000} y2={404 + i * 26} stroke="#1a1d24" strokeWidth={2} />
      ))}
      <Op>
      {[1715, 1905].map((ax) => (
        <g key={ax}>
          <rect x={ax - 42} y={412} width={84} height={136} fill="#4a5266" />
          <rect x={ax - 34} y={420} width={68} height={120} fill="#5a4a36" />
          {Array.from({ length: 5 }, (_, i) => (
            <line key={i} x1={ax - 26 + i * 13} y1={420} x2={ax - 26 + i * 13} y2={540} stroke="#1a1c22" strokeWidth={3} />
          ))}
        </g>
      ))}
      <path d={roundPath(1810, FLOOR, 108, 194)} fill="#16161c" />
      <path d="M 1744 440 A 66 66 0 0 1 1876 440" stroke="#4a5062" strokeWidth={14} fill="none" />
      <line x1={1810} y1={392} x2={1810} y2={FLOOR} stroke="#0c0c10" strokeWidth={3} />
      </Op>
      <line x1={1790} y1={322} x2={1830} y2={322} stroke={IRON} strokeWidth={3} />
      <line x1={1810} y1={322} x2={1810} y2={332} stroke={IRON} strokeWidth={3} />
      <rect x={1790} y={332} width={40} height={52} fill="#6e96d2" stroke={IRON} strokeWidth={3} />
      <line x1={1810} y1={332} x2={1810} y2={384} stroke={IRON} strokeWidth={1.5} />
      <Gargoyle x={1988} y={-290} s={1} />
    </g>
  );
};

// ---------------------------------------------------------------- D 折线屋顶住宅（2000–2400，轴线 2120 / 2290）
const House: React.FC = () => {
  const roof: Pt[] = [[2005, 80], [2075, -150], [2325, -150], [2395, 80]];
  return (
    <g>
      <rect x={2000} y={80} width={400} height={FLOOR - 80} fill="url(#houseWall)" />
      <polygon points={pts(roof)} fill="#1c2029" />
      <polyline points={pts(roof.slice(2))} stroke={RIM} strokeWidth={3} fill="none" />
      {/* 平顶两端的铁花尖刺压顶 */}
      {[2075, 2320].map((x) => (
        <polygon key={x} points={pts([[x, -150], [x + 6, -150], [x + 3, -186]])} fill={IRON} />
      ))}
      <Stack x0={2060} x1={2096} top={-220} base={-140} />
      <Stack x0={2296} x1={2336} top={-320} base={-140} pots={3} />
      {[2120, 2290].map((ax) => (
        <g key={ax}>
          <rect x={ax - 36} y={-90} width={72} height={160} fill="#30343f" />
          <polygon points={pts([[ax - 44, -90], [ax, -134], [ax + 44, -90]])} fill="#3c4150" />
          <Sash cx={ax} bottom={60} w={44} h={120} />
        </g>
      ))}
      <Pilaster x={2000} y0={80} y1={470} w={14} />
      <Pilaster x={2386} y0={80} y1={470} w={14} />
      <LitEdge x={2400} y0={80} y1={300} />
      <Plinth x0={2000} x1={2400} col="#3a3f4c" />
      {/* 凸窗：浅石框、侧面斜面、铅皮低坡顶（一层窗亮暗暖光） */}
      <polygon points={pts([[2054, 186], [2070, 168], [2170, 168], [2186, 186]])} fill="#262a34" />
      <polygon points={pts([[2062, 186], [2178, 186], [2170, 520], [2070, 520]])} fill="#3a404e" />
      <polygon points={pts([[2062, 186], [2076, 186], [2078, 520], [2070, 520]])} fill="#2a2e38" />
      <polygon points={pts([[2164, 186], [2178, 186], [2170, 520], [2162, 520]])} fill="#596276" />
      <Sash cx={2120} bottom={300} w={70} h={104} />
      <Sash cx={2120} bottom={500} w={70} h={104} fill={DIM} />
      {/* 二层右：落地窗 + 窗套；一层右：方门 + 扇形气窗（亮暗暖光） */}
      <Sash cx={2290} bottom={300} w={56} h={200} />
      <Op>
      <rect x={2262} y={410} width={56} height={FLOOR - 410} fill={WOOD} />
      <path d="M 2262 406 A 28 28 0 0 1 2318 406 Z" fill={DIM} />
      <path d="M 2256 406 A 34 34 0 0 1 2324 406" stroke={TRIM} strokeWidth={5} fill="none" />
      </Op>
    </g>
  );
};

// ---------------------------------------------------------------- 能站的面：每栋楼一种栏杆、一种托座
const Platform: React.FC<{ p: Plat }> = ({ p }) => {
  const [x0, b, y, kind] = p;
  const a = Math.max(x0, ART_X);
  const iron = (step: number, rail2 = false) => (
    <g>
      <line x1={a} y1={y - 38} x2={b} y2={y - 38} stroke={IRON} strokeWidth={2.5} />
      {Array.from({ length: Math.floor((b - a) / step) + 1 }, (_, i) => (
        <line key={i} x1={a + 6 + i * step} y1={y - 38} x2={a + 6 + i * step} y2={y} stroke={IRON} strokeWidth={2} />
      ))}
      {rail2 && <line x1={a} y1={y - 19} x2={b} y2={y - 19} stroke={IRON} strokeWidth={2} />}
    </g>
  );
  const slab = (thick = 22) => <rect x={a - 6} y={y} width={b - a + 12} height={thick} fill="url(#slab)" />;
  const edge = <line x1={a - 6} y1={y} x2={b + 6} y2={y} stroke={RIM} strokeWidth={4} />;
  const shadow = <polygon points={pts([[a - 6, y + 16], [b + 6, y + 16], [b - 34, y + 90], [a - 46, y + 90]])} fill="#06080d" opacity={0.45} filter="url(#b6)" />;
  if (kind === "gallery") return <line x1={a} y1={y} x2={b} y2={y} stroke={RIM} strokeWidth={4} />;
  if (kind === "ring") {
    const posts = Array.from({ length: Math.max(1, Math.floor((b - a) / 38)) }, (_, i) => a + 8 + i * 38);
    return (
      <g>
        {shadow}
        {slab()}
        <rect x={a} y={y - 40} width={b - a} height={8} fill="url(#slab)" />
        {posts.map((x) => <rect key={x} x={x} y={y - 32} width={9} height={32} fill="url(#slab)" />)}
        <rect x={b - 12} y={y - 46} width={16} height={46} fill="url(#slab)" />
        <polygon points={pts([[b - 30, y + 22], [b + 6, y + 22], [b - 4, y + 70]])} fill="url(#slab)" />
        {edge}
      </g>
    );
  }
  if (kind === "bridge") {
    const n = Math.floor((b - a) / 42);
    return (
      <g>
        <rect x={a} y={y} width={b - a} height={14} fill={IRON} />
        <line x1={a} y1={y - 38} x2={b} y2={y - 38} stroke={IRON} strokeWidth={2.5} />
        {Array.from({ length: Math.floor((b - a) / 18) + 1 }, (_, i) => (
          <line key={i} x1={a + i * 18} y1={y - 38} x2={a + i * 18} y2={y} stroke={IRON} strokeWidth={2} />
        ))}
        <line x1={a} y1={y + 50} x2={b} y2={y + 50} stroke={IRON} strokeWidth={3} />
        {Array.from({ length: n }, (_, i) => (
          <line key={i} x1={a + i * 42} y1={y + (i % 2 ? 50 : 14)} x2={a + i * 42 + 42} y2={y + (i % 2 ? 14 : 50)} stroke={IRON} strokeWidth={2} />
        ))}
        {edge}
      </g>
    );
  }
  if (x0 < 1000) {
    // 当铺：二层短铁阳台 + 两端细涡卷铁托；三层加厚素石檐 + 小托石
    return y > 150 ? (
      <g>
        {shadow}
        {slab()}
        {iron(32)}
        {[[a + 12, 1], [b - 12, -1]].map(([ex, s]) => (
          <path key={ex} d={bez([ex, y + 22], [ex, y + 70], [ex + s * 40, y + 22])} stroke={IRON} strokeWidth={3} fill="none" />
        ))}
        {edge}
      </g>
    ) : (
      <g>
        {shadow}
        {slab(20)}
        {[a + 30, (a + b) / 2 - 10, b - 50].map((bx) => (
          <polygon key={bx} points={pts([[bx, y + 20], [bx + 20, y + 20], [bx + 16, y + 44], [bx + 4, y + 44]])} fill="url(#slab)" />
        ))}
        {edge}
      </g>
    );
  }
  if (x0 < 1450) {
    // 船具行：木雨棚（铁托架）/ 平屋顶矮砖护墙 + 石压顶
    return y > 200 ? (
      <g>
        <polygon points={pts([[a - 10, y], [b + 10, y], [b + 10, y + 14], [a - 10, y + 22]])} fill="#2a2422" />
        {[a + 20, b - 20].map((ex) => (
          <g key={ex}>
            <line x1={ex} y1={y + 20} x2={ex} y2={y + 56} stroke={IRON} strokeWidth={3} />
            <line x1={ex} y1={y + 56} x2={ex + (ex < (a + b) / 2 ? 30 : -30)} y2={y + 20} stroke={IRON} strokeWidth={3} />
          </g>
        ))}
        <line x1={a - 10} y1={y} x2={b + 10} y2={y} stroke={RIM} strokeWidth={4} />
      </g>
    ) : (
      <g>
        <rect x={a} y={y - 22} width={b - a} height={28} fill="#2c282c" />
        <rect x={a - 4} y={y - 26} width={b - a + 8} height={8} fill="#545864" />
        <line x1={a} y1={y} x2={b} y2={y} stroke={RIM} strokeWidth={3} />
      </g>
    );
  }
  if (x0 < 2000) {
    // 警署：密排小托座；二层粗石栏、三层细铁栏、屋顶实心护墙（几个方孔）
    const corbels = Array.from({ length: Math.floor((b - a - 16) / 30) }, (_, i) => a + 8 + i * 30);
    return (
      <g>
        {shadow}
        {slab()}
        {corbels.map((bx) => <rect key={bx} x={bx} y={y + 22} width={12} height={18} fill="url(#slab)" />)}
        {y > 150 && (
          <g>
            <rect x={a} y={y - 46} width={b - a} height={12} fill="url(#slab)" />
            {Array.from({ length: Math.floor((b - a - 20) / 46) + 1 }, (_, i) => (
              <rect key={i} x={a + 10 + i * 46} y={y - 34} width={16} height={34} fill="url(#slab)" />
            ))}
          </g>
        )}
        {y <= 150 && y > -100 && iron(32)}
        {y <= -100 && (
          <g>
            <rect x={a} y={y - 40} width={b - a} height={40} fill="url(#slab)" />
            {Array.from({ length: 3 }, (_, i) => (
              <rect key={i} x={a + 40 + i * 90} y={y - 30} width={26} height={20} fill="#181c24" />
            ))}
          </g>
        )}
        {edge}
      </g>
    );
  }
  // 住宅：二层短铁阳台（两根细铁斜撑）/ 三层方格铁栏屋檐阳台（一排小飞檐托）/ 平顶低铁栏
  if (y < -100)
    return (
      <g>
        <line x1={a} y1={y - 22} x2={b} y2={y - 22} stroke={IRON} strokeWidth={2} />
        {Array.from({ length: Math.floor((b - a) / 24) + 1 }, (_, i) => (
          <line key={i} x1={a + i * 24} y1={y - 22} x2={a + i * 24} y2={y} stroke={IRON} strokeWidth={2} />
        ))}
        <line x1={a} y1={y} x2={b} y2={y} stroke={RIM} strokeWidth={3} />
      </g>
    );
  return (
    <g>
      {shadow}
      {slab()}
      {y > 150 ? iron(32) : iron(26, true)}
      {y > 150
        ? [[a + 14, 1], [b - 14, -1]].map(([ex, s]) => (
            <path key={ex} d={`M ${ex} ${y + 22} L ${ex} ${y + 70} L ${ex + s * 40} ${y + 22}`} stroke={IRON} strokeWidth={3} fill="none" />
          ))
        : Array.from({ length: Math.floor((b - a - 12) / 24) }, (_, i) => <rect key={i} x={a + 6 + i * 24} y={y + 22} width={8} height={10} fill="url(#slab)" />)}
      {edge}
    </g>
  );
};

// ---------------------------------------------------------------- 主画面
export const RainStreetRight: React.FC<Props> = ({ showLines, showOpenings }) => {
  const [sec, setSec] = useState<Section | null>(null);
  const [handle] = useState(() => delayRender("layout"));
  useEffect(() => {
    fetch(staticFile("layout.json"))
      .then((r) => r.json())
      .then((j) => {
        setSec(j.sections[0]);
        continueRender(handle);
      });
  }, [handle]);
  if (!sec) return null;
  const inFrame = (p: Plat) => p[1] >= X0 && p[0] <= X1;
  const plats = sec.platforms.filter((p) => inFrame(p) && p[1] > ART_X);
  const streets = sec.lamps.filter((l) => l[2] === "street" && l[0] >= ART_X && l[0] <= X1);
  const blocks = sec.blocks.filter((b) => b[0] >= ART_X && b[0] <= X1);
  const lampSpots: [number, number, number][] = [[860, 178, 0.8], [1540, 8, 0.8]];
  const warmSpots: [number, number, number][] = !showOpenings ? lampSpots : [[805, 490, 1], [860, 178, 0.8], [1540, 8, 0.8], [1905, -120, 0.6], [1340, 490, 0.9], [1115, 490, 0.5], [1715, 480, 0.4], [1905, 480, 0.4], [2120, 450, 0.5], [2290, 395, 0.5]];
  const svgProps = { viewBox: `${X0} ${Y0} ${VW} ${VH}`, width: 1672, height: 941, style: { position: "absolute" as const, left: 0, top: 0 } };
  return (
    <AbsoluteFill style={{ backgroundColor: "#0c0f15" }}>
      <Img src={staticFile("bg.png")} style={{ position: "absolute", left: 0, top: 0, width: 1672, height: 941 }} />
      <OpeningsCtx.Provider value={showOpenings}>
      <svg {...svgProps}>
        <defs>
          {[2, 6, 30, 60].map((s) => (
            <filter key={s} id={`b${s}`} filterUnits="userSpaceOnUse" x={X0 - 300} y={Y0 - 300} width={VW + 600} height={VH + 600}>
              <feGaussianBlur stdDeviation={s} />
            </filter>
          ))}
          {[
            ["pawnWall", "#30343f", "#0e1016", -300, FLOOR],
            ["pawnGable", "#3a4050", "#2c3140", -520, -300],
            ["brickWall", "#3a3236", "#0f0c0f", 120, FLOOR],
            ["policeWall", "#262a34", "#0c0e12", -255, FLOOR],
            ["policeRoof", "#262c3a", "#0f1118", -600, -255],
            ["policePier", "#3a404e", "#14161c", -255, 470],
            ["houseWall", "#2c3039", "#101116", 80, FLOOR],
            ["alleyBack", "#2c3340", "#1e232e", -120, FLOOR],
            ["pilaster", "#5a6070", "#1a1c24", -300, FLOOR],
            ["slab", "#545a6a", "#2a2e3a", -300, 620],
          ].map(([id, c0, c1, y0, y1]) => (
            <linearGradient key={id as string} id={id as string} gradientUnits="userSpaceOnUse" x1={0} y1={y0 as number} x2={0} y2={y1 as number}>
              <stop offset="0" stopColor={c0 as string} />
              <stop offset="1" stopColor={c1 as string} />
            </linearGradient>
          ))}
          <linearGradient id="warmWin" x1={0} y1={0} x2={0} y2={1}>
            <stop offset="0" stopColor="#705a3c" />
            <stop offset="1" stopColor="#463826" />
          </linearGradient>
          <linearGradient id="litEdge" x1={0} y1={0} x2={1} y2={0}>
            <stop offset="0" stopColor="#96a2bc" stopOpacity={0} />
            <stop offset="1" stopColor="#96a2bc" stopOpacity={0.55} />
          </linearGradient>
          <radialGradient id="craneFog">
            <stop offset="0" stopColor="#8a98b4" stopOpacity={0.5} />
            <stop offset="1" stopColor="#8a98b4" stopOpacity={0} />
          </radialGradient>
          <radialGradient id="warmHalo">
            <stop offset="0" stopColor="#c8a060" stopOpacity={0.32} />
            <stop offset="1" stopColor="#c8a060" stopOpacity={0} />
          </radialGradient>
          <radialGradient id="blueHalo">
            <stop offset="0" stopColor="#5a86d0" stopOpacity={0.4} />
            <stop offset="1" stopColor="#5a86d0" stopOpacity={0} />
          </radialGradient>
        </defs>
        {/* 背景压暗：右边缘收住；吊车背后一束亮雾（全图唯一的大面积亮处） */}
        <rect x={X0} y={Y0} width={VW} height={FLOOR - Y0} fill="#0a0d14" opacity={0.3} />
        <rect x={2395} y={Y0} width={X1 - 2395} height={FLOOR - Y0} fill="#141820" opacity={0.55} filter="url(#b30)" />
        <ellipse cx={510} cy={280} rx={240} ry={330} fill="url(#craneFog)" />
        <Alley />
        <Crane />
        <Pawnshop />
        <Chandlery />
        <Police />
        <House />
        {blocks.map((b) => (
          <g key={b[0]}>
            <rect x={b[0]} y={b[2]} width={b[1] - b[0]} height={FLOOR - b[2]} fill="url(#slab)" />
            {Array.from({ length: Math.floor((FLOOR - b[2]) / 30) }, (_, i) => (
              <line key={i} x1={b[0]} y1={b[2] + 30 + i * 30} x2={b[1]} y2={b[2] + 30 + i * 30} stroke="#20242e" strokeWidth={2} />
            ))}
            <Band x0={b[0] - 6} x1={b[1] + 6} y={b[2]} h={12} />
            <line x1={b[0] - 6} y1={b[2]} x2={b[1] + 6} y2={b[2]} stroke={RIM} strokeWidth={3} />
          </g>
        ))}
        {plats.map((p) => <Platform key={`${p[0]}:${p[2]}`} p={p} />)}
        {/* 暖光晕、警灯冷光 */}
        {warmSpots.map(([x, y, s]) => <ellipse key={`${x}:${y}`} cx={x} cy={y} rx={110} ry={140} fill="url(#warmHalo)" opacity={s} />)}
        <ellipse cx={1810} cy={358} rx={70} ry={70} fill="url(#blueHalo)" />
        {/* 路灯：两倍人高 */}
        {streets.map(([x, y]) => (
          <g key={x}>
            <ellipse cx={x} cy={y - 320} rx={190} ry={200} fill="url(#warmHalo)" />
            <ellipse cx={x} cy={y + 8} rx={160} ry={16} fill="url(#warmHalo)" />
            <rect x={x - 6} y={y - 300} width={12} height={300} fill="#0a0b0e" />
            <rect x={x - 14} y={y - 40} width={28} height={40} fill="#0a0b0e" />
            <line x1={x - 22} y1={y - 290} x2={x + 22} y2={y - 290} stroke="#0a0b0e" strokeWidth={3} />
            <polygon points={pts([[x - 22, y - 342], [x + 22, y - 342], [x, y - 370]])} fill="#0a0b0e" />
            <polygon points={pts([[x - 18, y - 342], [x + 18, y - 342], [x + 12, y - 298], [x - 12, y - 298]])} fill="#f8e0a8" />
          </g>
        ))}
        {/* 街面 / 冷蓝湿反光带 / 河岸护墙 / 河 */}
        <rect x={ART_X} y={500} width={X1 - ART_X} height={80} fill="#4a6ea4" opacity={0.3} filter="url(#b30)" />
        <rect x={ART_X} y={FLOOR} width={X1 - ART_X} height={26} fill="#2c313c" />
        <line x1={ART_X} y1={FLOOR + 1} x2={X1} y2={FLOOR + 1} stroke="#6e7890" strokeWidth={2} />
        <rect x={ART_X} y={FLOOR + 26} width={X1 - ART_X} height={70} fill="#161921" />
        <rect x={ART_X} y={FLOOR + 26} width={X1 - ART_X} height={8} fill="#464c5a" />
        {Array.from({ length: 19 }, (_, i) => ART_X + 40 + i * 120).map((bx) => (
          <g key={bx}>
            <line x1={bx} y1={FLOOR + 34} x2={bx} y2={FLOOR + 62} stroke="#0c0e14" strokeWidth={2} />
            <line x1={bx + 60} y1={FLOOR + 62} x2={bx + 60} y2={FLOOR + 96} stroke="#0c0e14" strokeWidth={2} />
          </g>
        ))}
        <line x1={ART_X} y1={FLOOR + 62} x2={X1} y2={FLOOR + 62} stroke="#0c0e14" strokeWidth={2} />
        <rect x={X0} y={FLOOR + 96} width={VW} height={200} fill="#0c0f15" />
        {[...streets.map(([x]) => [x, "#8a5c26", 24]), [0, "#8a2c14", 80], [805, "#4a3418", 40], [1340, "#3e2c16", 40], [1810, "#1c2c4a", 20]].map(([x, c, w]) => (
          <rect key={`r${x}`} x={(x as number) - (w as number) / 2} y={FLOOR + 100} width={w as number} height={130} fill={c as string} filter="url(#b6)" />
        ))}
        {/* 护墙上的铸铁系船桩 ×2 + 系船铁环；封印外的下河石阶（不比街面亮） */}
        {[900, 1900].map((bx) => (
          <g key={bx}>
            <rect x={bx - 10} y={FLOOR - 30} width={20} height={32} rx={5} fill="#1a1c22" />
            <ellipse cx={bx} cy={FLOOR - 31} rx={14} ry={7} fill="#1a1c22" />
          </g>
        ))}
        <ellipse cx={1400} cy={FLOOR + 65} rx={14} ry={15} fill="none" stroke="#2a2c34" strokeWidth={3} />
        {Array.from({ length: 5 }, (_, i) => (
          <g key={i}>
            <rect x={2440 + i * 18} y={FLOOR + 30 + i * 14} width={2540 - 2440 - i * 18} height={14} fill="#22262f" />
            <line x1={2440 + i * 18} y1={FLOOR + 30 + i * 14} x2={2540} y2={FLOOR + 30 + i * 14} stroke="#505868" strokeWidth={2} />
          </g>
        ))}
        {[[520, 90], [1240, 110], [2150, 90]].map(([px, pw]) => (
          <ellipse key={px} cx={px} cy={FLOOR + 13} rx={pw} ry={7} fill="#5c5a5c" opacity={0.5} filter="url(#b2)" />
        ))}
      </svg>
      </OpeningsCtx.Provider>
      {/* 左边的成图段（钟楼右半）盖在最上面：GPT 照着这一段往右接 */}
      <Img src={staticFile("strip.png")} style={{ position: "absolute", left: 0, top: 1 }} />
      {showLines && (
        <svg {...svgProps}>
          {sec.platforms.filter(inFrame).map((p) => (
            <line key={`y${p[0]}:${p[2]}`} x1={p[0]} y1={p[2]} x2={p[1]} y2={p[2]} stroke="#ffd400" strokeWidth={6.5} />
          ))}
          {sec.blocks.filter(inFrame).map((b) => (
            <line key={`yb${b[0]}`} x1={b[0] + (b[1] - b[0]) * 0.24} y1={b[2]} x2={b[1] - (b[1] - b[0]) * 0.24} y2={b[2]} stroke="#ffd400" strokeWidth={6.5} />
          ))}
        </svg>
      )}
    </AbsoluteFill>
  );
};
