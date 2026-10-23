import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame, interpolate, Easing} from 'remotion';
const LAYERS: {name: string; par: number; add: boolean}[] = [
  {name: 'sky', par: 0, add: false}, {name: 'far_mountains', par: 0.05, add: false},
  {name: 'hills_pagoda', par: 0.1, add: false}, {name: 'sky_lanterns', par: 0.08, add: true},
  {name: 'horizon_mist', par: 0.15, add: false}, {name: 'town', par: 0.25, add: false},
  {name: 'moon_path', par: 0, add: true}, {name: 'bridge', par: 0.35, add: false},
  {name: 'boat', par: 0.5, add: false}, {name: 'willow_mid', par: 0.6, add: false},
  {name: 'fog_band', par: 0.9, add: false}, {name: 'walkway', par: 1.0, add: false},
  {name: 'walk_light', par: 1.0, add: true}, {name: 'fireflies', par: 1.0, add: true},
  {name: 'foreground', par: 1.4, add: false},
];
const wob = (f: number, a: number, b: number, c: number) => Math.sin(f * a) * 0.5 + Math.sin(f * b + 1.3) * 0.3 + Math.sin(f * c + 2.1) * 0.2;
export const Parallax: React.FC = () => {
  const f = useCurrentFrame();
  const pan = interpolate(f, [0, 239], [0, 440], {easing: Easing.inOut(Easing.sin)});
  return (
    <AbsoluteFill style={{backgroundColor: '#05080a', overflow: 'hidden'}}>
      <div style={{position: 'absolute', width: 1920, height: 1080, transform: 'scale(0.6666667)', transformOrigin: '0 0', overflow: 'hidden'}}>
        {LAYERS.map((L) => {
          let x = -pan * L.par, y = 0, op = 1;
          if (L.name === 'fog_band') x -= f * 0.5;
          if (L.name === 'horizon_mist') x -= f * 0.15;
          if (L.name === 'walk_light') op = 0.88 + 0.12 * wob(f, 0.31, 0.77, 1.9);
          if (L.name === 'fireflies') { y = Math.sin(f * 0.05) * 6; op = 0.7 + 0.3 * wob(f, 0.13, 0.29, 0.5); }
          if (L.name === 'moon_path') op = 0.85 + 0.15 * wob(f, 0.2, 0.45, 0.9);
          if (L.name === 'sky_lanterns') y = -f * 0.08;
          return (
            <Img key={L.name} src={staticFile(L.name + '.png')}
              style={{position: 'absolute', left: 0, top: 0, width: 2560, height: 1080,
                transform: `translate(${x}px, ${y}px)`, opacity: op,
                mixBlendMode: L.add ? 'plus-lighter' : 'normal'}} />
          );
        })}
        <div style={{position: 'absolute', inset: 0,
          background: 'radial-gradient(ellipse 62% 75% at 50% 45%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.38) 100%)'}} />
      </div>
    </AbsoluteFill>
  );
};
