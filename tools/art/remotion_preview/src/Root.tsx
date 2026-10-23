import React from 'react';
import {Composition} from 'remotion';
import {Parallax} from './Parallax';
export const Root: React.FC = () => (
  <Composition id="Parallax" component={Parallax} durationInFrames={240} fps={30} width={1280} height={720} />
);
