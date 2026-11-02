// 「雨夜河岸街」钟楼广场往东的走廊（x 2560 ~ 4000）的明暗草图：GPT 照着画成图。
// 画面 = 世界 x 1290 ~ 4000、y −700 ~ 826（1672×941，和左半边同一比例），左边 1290 ~ 2560 是已经画好的成图（public/corridor_strip.png）。
// 第三版（10-30，哥特石廊桥）：走廊是廊桥的起点。左边一座哥特门楼（两座平顶垛口八角角楼、尖拱门洞里半升的铁闸、石像鬼），
// 右边石廊桥从门楼伸出去、往右出画：桥下尖拱桥洞（第一孔透雾 + 路灯，第二孔锁着铁栅门），桥面上是一条有顶的哥特廊道
// （尖拱连拱按桥墩分成开间、扶壁、石板陡屋顶）。能站的面：门楼二层挑台 300、屋顶垛口平台 −260、廊道地面 20。
import React, { useEffect, useState } from "react";
import { AbsoluteFill, Img, continueRender, delayRender, staticFile } from "remotion";
import { Band, DIM, GLASS, Gargoyle, IRON, LitEdge, Op, OpeningsCtx, Plat, Plinth, RIM, Section, WARM, pts } from "./RainStreetRight";

// matte：只出近景轮廓（白 = 近景，黑 = 天空 / 远景 / 河），给成图抠图当遮罩用
export type CorridorProps = { readonly showLines: boolean; readonly showOpenings: boolean; readonly matte?: boolean };

const X0 = 1290;
const X1 = 4000;
const Y0 = -700;
const VW = X1 - X0;
const VH = (VW * 941) / 1672;
const FLOOR = 580;
const ART_X = 2560;
const DECK = 20; // 廊道地面
const EAVE = -170; // 廊道檐口
const RIDGE = -245; // 廊道屋脊
const GATE: [number, number] = [2600, 3040]; // 门楼主体
const TURRETS: [number, number][] = [[2572, 2662], [2978, 3068]];
const PIERS: [number, number][] = [[3060, 3150], [3510, 3600], [3960, 4050]];
const SPRING = 380; // 桥洞尖拱起拱线（拱高要明显大于半跨，才读得出尖拱）
const APEX = 100; // 桥洞尖拱顶

/** 尖拱（两段圆弧）：a ~ b，起拱 spring，拱顶 apex，底到 bottom */
const pointed = (a: number, b: number, spring: number, apex: number, bottom: number) => {
  const half = (b - a) / 2;
  const rise = spring - apex;
  const r = (half * half + rise * rise) / (2 * half); // 两段圆弧圆心落在起拱线上、互相越过中线 → 尖拱
  return `M ${a} ${bottom} L ${a} ${spring} A ${r} ${r} 0 0 1 ${a + half} ${apex} A ${r} ${r} 0 0 1 ${b} ${spring} L ${b} ${bottom} Z`;
};

// ---------------------------------------------------------------- 第一孔后面：雾里的普通坡顶楼（只从桥洞里看得到）
const BEHIND: [number, number, number, number][] = [
  // x0, x1, 檐口 y, 屋顶高（人字坡，高不超过宽的一半；0 = 平顶带烟囱）
  [3140, 3250, 300, 50], [3250, 3360, 250, 0], [3360, 3520, 330, 60],
];
const Behind: React.FC = () => (
  <g>
    <rect x={3140} y={60} width={380} height={FLOOR - 60} fill="#2c3650" />
    <ellipse cx={3330} cy={250} rx={200} ry={260} fill="url(#archFog)" />
    {BEHIND.map(([a, b, y, h]) => (
      <g key={a}>
        <rect x={a} y={y} width={b - a} height={FLOOR - y} fill="#1c2436" />
        {h > 0 ? (
          <>
            <polygon points={pts([[a - 6, y], [b + 6, y], [(a + b) / 2, y - h]])} fill="#1c2436" />
            <rect x={b - 34} y={y - h - 10} width={20} height={h} fill="#1c2436" />
          </>
        ) : (
          <>
            <rect x={a + 14} y={y - 46} width={26} height={46} fill="#1c2436" />
            <rect x={b - 44} y={y - 34} width={22} height={34} fill="#1c2436" />
          </>
        )}
      </g>
    ))}
    <rect x={3140} y={330} width={380} height={FLOOR - 330} fill="url(#fogUp)" />
  </g>
);

// ---------------------------------------------------------------- 门楼
const Gatehouse: React.FC = () => {
  const [a, b] = GATE;
  return (
    <g>
      {/* 主体 + 屋顶垛口（垛口在平台后面，平台面是 −260） */}
      <rect x={a} y={-260} width={b - a} height={FLOOR + 260} fill="url(#gateWall)" />
      {Array.from({ length: 7 }, (_, i) => (
        <rect key={i} x={a + 40 + i * 56} y={-300} width={30} height={40} fill="#262c3a" />
      ))}
      <Band x0={a} x1={b} y={DECK} h={14} />
      {/* 两座八角角楼：平顶垛口，不做尖顶；只开一条窄缝窗 */}
      {TURRETS.map(([ta, tb]) => (
        <g key={ta}>
          <rect x={ta} y={-390} width={tb - ta} height={FLOOR + 390} fill="url(#turret)" />
          <line x1={ta + 22} y1={-390} x2={ta + 22} y2={470} stroke="#141821" strokeWidth={2} />
          <line x1={tb - 22} y1={-390} x2={tb - 22} y2={470} stroke="#141821" strokeWidth={2} />
          <rect x={ta - 6} y={-404} width={tb - ta + 12} height={14} fill="#3c4354" />
          {[0, 1, 2].map((i) => (
            <rect key={i} x={ta - 4 + i * 36} y={-436} width={24} height={32} fill="#2a303c" />
          ))}
          <Op>
            <rect x={(ta + tb) / 2 - 5} y={-330} width={10} height={60} fill={GLASS} />
            <rect x={(ta + tb) / 2 - 5} y={-120} width={10} height={60} fill={GLASS} />
          </Op>
          <line x1={tb - 3} y1={-390} x2={tb - 3} y2={470} stroke="#8a96b0" strokeWidth={2} />
          <Plinth x0={ta} x1={tb} col="#272c38" />
        </g>
      ))}
      <Plinth x0={a} x1={b} col="#2a2f3c" />
      {/* 尖拱门洞（深处一点雾光）+ 半升的铁闸 */}
      <path d={pointed(2725, 2915, 470, 310, FLOOR)} fill="#4c5466" />
      <path d={pointed(2740, 2900, 474, 328, FLOOR)} fill="#0c0e14" />
      <ellipse cx={2820} cy={500} rx={46} ry={70} fill="url(#archFog)" opacity={0.7} />
      {Array.from({ length: 7 }, (_, i) => (
        <line key={i} x1={2752 + i * 23} y1={i === 0 || i === 6 ? 400 : 350} x2={2752 + i * 23} y2={420} stroke={IRON} strokeWidth={4} />
      ))}
      <line x1={2742} y1={420} x2={2898} y2={420} stroke={IRON} strokeWidth={4} />
      {/* 二层：挑台后一对尖拱窗（右边一扇暗暖）；三层：一扇高的尖拱花窗 */}
      <Op>
        {[2730, 2910].map((cx, i) => (
          <g key={cx}>
            <path d={pointed(cx - 30, cx + 30, 170, 110, 290)} fill="#5c6274" />
            <path d={pointed(cx - 22, cx + 22, 176, 124, 290)} fill={i === 1 ? "#6a5232" : GLASS} />
            <line x1={cx} y1={130} x2={cx} y2={290} stroke="#283040" strokeWidth={2.5} />
          </g>
        ))}
        <path d={pointed(2760, 2880, -120, -250, -10)} fill="#5c6274" />
        <path d={pointed(2770, 2870, -116, -236, -10)} fill={GLASS} />
        <line x1={2820} y1={-200} x2={2820} y2={-10} stroke="#283040" strokeWidth={2.5} />
        <line x1={2770} y1={-90} x2={2870} y2={-90} stroke="#283040" strokeWidth={2.5} />
      </Op>
      {/* 门两侧两盏壁灯 */}
      {[2700, 2940].map((x) => (
        <g key={x}>
          <rect x={x - 8} y={392} width={16} height={26} fill={WARM} />
          <line x1={x} y1={392} x2={x} y2={378} stroke={IRON} strokeWidth={3} />
        </g>
      ))}
      {/* 屋顶两角的石像鬼 */}
      <Gargoyle x={a + 4} y={-250} s={-0.8} />
      <Gargoyle x={b - 4} y={-250} s={0.8} />
      <LitEdge x={b} y0={-260} y1={470} />
    </g>
  );
};

// ---------------------------------------------------------------- 石廊桥：桥身 + 桥洞
const Bridge: React.FC = () => {
  const holes = [pointed(3150, 3510, SPRING, APEX, FLOOR), pointed(3600, 3960, SPRING, APEX, FLOOR)];
  return (
    <g>
      <path d={`M 3060 ${DECK} L ${X1 + 20} ${DECK} L ${X1 + 20} ${FLOOR} L 3060 ${FLOOR} Z ${holes.join(" ")}`} fill="url(#bridge)" fillRule="evenodd" />
      {/* 拱圈：一圈浅一点的石券 */}
      {[[3150, 3510], [3600, 3960]].map(([a, b]) => (
        <path key={a} d={pointed(a - 10, b + 10, SPRING, APEX - 16, SPRING)} stroke="#4c5466" strokeWidth={18} fill="none" />
      ))}
      {/* 墩子：右边缘月光湿亮边 + 石基 */}
      {PIERS.map(([a, b]) => (
        <g key={a}>
          <rect x={a + 10} y={SPRING} width={b - a - 20} height={FLOOR - SPRING} fill="url(#pier)" />
          <LitEdge x={b} y0={SPRING - 60} y1={470} w={10} />
          <Plinth x0={a} x1={b} col="#262b36" />
        </g>
      ))}
      {/* 廊道地面下一排托石 */}
      <Band x0={3060} x1={X1 + 20} y={DECK} h={20} />
      {Array.from({ length: 24 }, (_, i) => 3080 + i * 40).map((x) => (
        <rect key={x} x={x} y={DECK + 20} width={16} height={18} fill="#2c3240" />
      ))}
      {/* 第二孔：里面黑，整孔一道锁着的铁栅门（栅条按拱形裁） */}
      <clipPath id="hole2">
        <path d={holes[1]} />
      </clipPath>
      <g clipPath="url(#hole2)">
        <rect x={3600} y={APEX} width={360} height={FLOOR - APEX} fill="#0c0e14" />
        {Array.from({ length: 13 }, (_, i) => (
          <line key={i} x1={3612 + i * 28} y1={APEX} x2={3612 + i * 28} y2={FLOOR} stroke={IRON} strokeWidth={4} />
        ))}
        <line x1={3600} y1={SPRING} x2={3960} y2={SPRING} stroke={IRON} strokeWidth={5} />
      </g>
      <rect x={3770} y={440} width={20} height={26} fill="#1e1e22" />
    </g>
  );
};

// ---------------------------------------------------------------- 桥面上的有顶哥特廊道（按桥墩分开间：每开间三孔尖拱，开间之间一道扶壁）
const Gallery: React.FC = () => {
  const bays = [3105, 3555, 4005];
  return (
    <g>
      {/* 后墙（暗）+ 檐口 + 石板陡屋顶 */}
      <rect x={3060} y={EAVE} width={X1 - 3060 + 20} height={DECK - EAVE} fill="#121620" />
      <polygon points={pts([[3050, EAVE], [X1 + 20, EAVE], [X1 + 20, RIDGE], [3090, RIDGE]])} fill="url(#slate)" />
      <line x1={3090} y1={RIDGE} x2={X1 + 20} y2={RIDGE} stroke="#7a86a0" strokeWidth={2} />
      {/* 每个开间正中一个小山墙（宽矮，不是尖顶），把屋脊打断成节奏；山墙上一扇小尖窗 */}
      {bays.slice(0, -1).map((bx) => (
        <g key={`g${bx}`}>
          <polygon points={pts([[bx + 130, EAVE + 4], [bx + 320, EAVE + 4], [bx + 225, EAVE - 120]])} fill="#262d3e" />
          <line x1={bx + 225} y1={EAVE - 120} x2={bx + 320} y2={EAVE + 4} stroke="#8a96b0" strokeWidth={2} />
          <path d={pointed(bx + 210, bx + 240, EAVE - 40, EAVE - 72, EAVE - 6)} fill="#0c0f16" />
        </g>
      ))}
      <rect x={3050} y={EAVE - 4} width={X1 - 3050 + 20} height={14} fill="#3a4152" />
      {/* 前面的连拱：每开间三孔，开间之间扶壁 */}
      {bays.slice(0, -1).map((bx, k) => (
        <g key={bx}>
          {[0, 1, 2].map((i) => {
            const cx = bx + 85 + i * 140;
            return (
              <g key={i}>
                <path d={`M ${cx - 70} ${DECK} L ${cx - 70} ${EAVE + 10} L ${cx + 70} ${EAVE + 10} L ${cx + 70} ${DECK} Z`} fill="#2c3242" />
                <path d={pointed(cx - 46, cx + 46, -70, -140, -6)} fill="#0c0f16" />
                {/* 第二开间中间一孔里挂一盏暗暖的小提灯 */}
                {k === 1 && i === 1 && <rect x={cx - 7} y={-96} width={14} height={20} fill={DIM} />}
              </g>
            );
          })}
        </g>
      ))}
      {/* 廊道矮墙（站人的面在 20，矮墙只到膝盖、在人后面） */}
      <rect x={3060} y={-6} width={X1 - 3060 + 20} height={26} fill="#353c4c" />
      {/* 扶壁：压在桥墩正上方，斜顶 */}
      {bays.map((bx) => (
        <g key={bx}>
          <rect x={bx - 22} y={EAVE - 30} width={44} height={DECK - EAVE + 30} fill="#2e3444" />
          <polygon points={pts([[bx - 26, EAVE - 30], [bx + 26, EAVE - 30], [bx + 26, EAVE - 56]])} fill="#3a4152" />
          <line x1={bx + 22} y1={EAVE - 30} x2={bx + 22} y2={DECK} stroke="#8a96b0" strokeWidth={2} />
        </g>
      ))}
    </g>
  );
};

// ---------------------------------------------------------------- 能站的面
const Platform: React.FC<{ p: Plat }> = ({ p }) => {
  const [x0, b, y, kind] = p;
  const a = Math.max(x0, ART_X);
  const edge = <line x1={a - 6} y1={y} x2={b + 6} y2={y} stroke={RIM} strokeWidth={4} />;
  const shadow = <polygon points={pts([[a - 6, y + 16], [b + 6, y + 16], [b - 34, y + 90], [a - 46, y + 90]])} fill="#06080d" opacity={0.45} filter="url(#c6)" />;
  if (kind === "balcony")
    // 门楼二层石挑台：石板 + 石栏杆（宝瓶柱）
    return (
      <g>
        {shadow}
        <rect x={a - 6} y={y} width={b - a + 12} height={22} fill="url(#slab2)" />
        <rect x={a} y={y - 40} width={b - a} height={8} fill="#4a5262" />
        {Array.from({ length: Math.floor((b - a) / 24) }, (_, i) => (
          <rect key={i} x={a + 8 + i * 24} y={y - 32} width={10} height={32} fill="#3c4354" />
        ))}
        {edge}
      </g>
    );
  if (kind === "gallery")
    // 廊道地面：只要一道连续的冷亮边
    return <g>{edge}</g>;
  // 门楼屋顶垛口平台
  return (
    <g>
      <rect x={a - 6} y={y} width={b - a + 12} height={16} fill="url(#slab2)" />
      {edge}
    </g>
  );
};

export const Corridor: React.FC<CorridorProps> = ({ showLines, showOpenings, matte = false }) => {
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
  const plats = sec.platforms.filter((p) => inFrame(p) && p[0] >= ART_X - 20);
  const streets = sec.lamps.filter((l) => l[2] === "street" && l[0] >= ART_X && l[0] <= X1);
  const svgProps = { viewBox: `${X0} ${Y0} ${VW} ${VH}`, width: 1672, height: 941, style: { position: "absolute" as const, left: 0, top: 0 } };
  return (
    <AbsoluteFill style={{ backgroundColor: matte ? "#000" : "#0c0f15" }}>
      {!matte && <Img src={staticFile("corridor_bg.png")} style={{ position: "absolute", left: 0, top: 0, width: 1672, height: 941 }} />}
      <OpeningsCtx.Provider value={showOpenings}>
        <svg {...svgProps}>
          <defs>
            {[2, 6, 30, 60].map((s) => (
              <filter key={s} id={`c${s}`} filterUnits="userSpaceOnUse" x={X0 - 300} y={Y0 - 300} width={VW + 600} height={VH + 600}>
                <feGaussianBlur stdDeviation={s} />
              </filter>
            ))}
            {[
              ["gateWall", "#2e3444", "#0e1118", -260, FLOOR],
              ["turret", "#2a3040", "#0e1016", -390, FLOOR],
              ["bridge", "#262c3a", "#0c0f15", DECK, FLOOR],
              ["pier", "#2a3142", "#0f1218", SPRING, FLOOR],
              ["slate", "#283044", "#1a2030", RIDGE, EAVE],
              ["slab2", "#545a6a", "#2a2e3a", -150, 620],
              ["street", "#6a7896", "#3a4254", FLOOR, FLOOR + 26],
            ].map(([id, c0, c1, y0, y1]) => (
              <linearGradient key={id as string} id={id as string} gradientUnits="userSpaceOnUse" x1={0} y1={y0 as number} x2={0} y2={y1 as number}>
                <stop offset="0" stopColor={c0 as string} />
                <stop offset="1" stopColor={c1 as string} />
              </linearGradient>
            ))}
            <linearGradient id="fogUp" gradientUnits="userSpaceOnUse" x1={0} y1={330} x2={0} y2={FLOOR}>
              <stop offset="0" stopColor="#7c8cac" stopOpacity={0} />
              <stop offset="1" stopColor="#7c8cac" stopOpacity={0.6} />
            </linearGradient>
            <linearGradient id="litEdge" x1={0} y1={0} x2={1} y2={0}>
              <stop offset="0" stopColor="#96a2bc" stopOpacity={0} />
              <stop offset="1" stopColor="#96a2bc" stopOpacity={0.55} />
            </linearGradient>
            <linearGradient id="pilaster" gradientUnits="userSpaceOnUse" x1={0} y1={-300} x2={0} y2={FLOOR}>
              <stop offset="0" stopColor="#5a6070" />
              <stop offset="1" stopColor="#1a1c24" />
            </linearGradient>
            <radialGradient id="archFog">
              <stop offset="0" stopColor="#9aa8c4" stopOpacity={0.6} />
              <stop offset="1" stopColor="#9aa8c4" stopOpacity={0} />
            </radialGradient>
            <filter id="white">
              <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 1 0" />
            </filter>
            <radialGradient id="warmHalo">
              <stop offset="0" stopColor="#c8a060" stopOpacity={0.32} />
              <stop offset="1" stopColor="#c8a060" stopOpacity={0} />
            </radialGradient>
          </defs>
          {!matte && <rect x={X0} y={Y0} width={VW} height={FLOOR - Y0} fill="#0a0d14" opacity={0.3} />}
          <g filter={matte ? "url(#white)" : undefined}>
          <Behind />
          <Bridge />
          <Gallery />
          <Gatehouse />
          {plats.map((p) => <Platform key={`${p[0]}:${p[2]}`} p={p} />)}
          {/* 暖光晕：门两侧壁灯、二层一扇窗、廊道里的小提灯（都小） */}
          {!matte && [[2700, 405, 0.6], [2940, 405, 0.6], ...(showOpenings ? [[2910, 230, 0.35], [3780, -86, 0.4]] : [])].map(([x, y, s]) => (
            <ellipse key={`${x}:${y}`} cx={x} cy={y} rx={80} ry={100} fill="url(#warmHalo)" opacity={s} />
          ))}
          {/* 路灯（第一孔下） */}
          {streets.map(([x, y]) => (
            <g key={x}>
              {!matte && <ellipse cx={x} cy={y - 320} rx={170} ry={180} fill="url(#warmHalo)" />}
              <rect x={x - 6} y={y - 300} width={12} height={300} fill="#0a0b0e" />
              <rect x={x - 14} y={y - 40} width={28} height={40} fill="#0a0b0e" />
              <line x1={x - 22} y1={y - 290} x2={x + 22} y2={y - 290} stroke="#0a0b0e" strokeWidth={3} />
              <polygon points={pts([[x - 22, y - 342], [x + 22, y - 342], [x, y - 370]])} fill="#0a0b0e" />
              <polygon points={pts([[x - 18, y - 342], [x + 18, y - 342], [x + 12, y - 298], [x - 12, y - 298]])} fill="#f8e0a8" />
            </g>
          ))}
          {/* 湿石板街面：和左边成图同档，顶边一道冷亮湿边，灯下一摊暖反光 */}
          {!matte && <rect x={ART_X} y={500} width={X1 - ART_X} height={80} fill="#4a6ea4" opacity={0.36} filter="url(#c30)" />}
          <rect x={ART_X} y={FLOOR} width={X1 - ART_X} height={26} fill="url(#street)" />
          <line x1={ART_X} y1={FLOOR + 1} x2={X1} y2={FLOOR + 1} stroke="#a8b6d0" strokeWidth={3} />
          {[...streets.map(([x]) => x), 2700, 2940].map((x) => <ellipse key={`p${x}`} cx={x} cy={FLOOR + 12} rx={x === 2700 || x === 2940 ? 70 : 120} ry={10} fill="#d8a860" opacity={0.5} filter="url(#c6)" />)}
          {[3060, 3780].map((x) => <ellipse key={`w${x}`} cx={x} cy={FLOOR + 10} rx={150} ry={8} fill="#8ea4cc" opacity={0.45} filter="url(#c6)" />)}
          {/* 河岸护墙 / 河 */}
          <rect x={ART_X} y={FLOOR + 26} width={X1 - ART_X} height={70} fill="#161921" />
          <rect x={ART_X} y={FLOOR + 26} width={X1 - ART_X} height={8} fill="#464c5a" />
          {Array.from({ length: 12 }, (_, i) => ART_X + 40 + i * 120).map((bx) => (
            <g key={bx}>
              <line x1={bx} y1={FLOOR + 34} x2={bx} y2={FLOOR + 62} stroke="#0c0e14" strokeWidth={2} />
              <line x1={bx + 60} y1={FLOOR + 62} x2={bx + 60} y2={FLOOR + 96} stroke="#0c0e14" strokeWidth={2} />
            </g>
          ))}
          <line x1={ART_X} y1={FLOOR + 62} x2={X1} y2={FLOOR + 62} stroke="#0c0e14" strokeWidth={2} />
          {!matte && <rect x={X0} y={FLOOR + 96} width={VW} height={200} fill="#0c0f15" />}
          {!matte && [...streets.map(([x]) => x), 2700, 2940].map((x) => <rect key={`r${x}`} x={x - 10} y={FLOOR + 100} width={20} height={110} fill="#8a5c26" filter="url(#c6)" />)}
          {/* 护墙顶一根铸铁系船桩 */}
          <rect x={3460} y={FLOOR - 30} width={20} height={32} rx={5} fill="#1a1c22" />
          <ellipse cx={3470} cy={FLOOR - 31} rx={14} ry={7} fill="#1a1c22" />
          </g>
        </svg>
      </OpeningsCtx.Provider>
      {!matte && <Img src={staticFile("corridor_strip.png")} style={{ position: "absolute", left: 0, top: 1 }} />}
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
