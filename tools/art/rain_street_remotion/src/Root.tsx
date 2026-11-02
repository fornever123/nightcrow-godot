import { Still } from "remotion";
import { RainStreetRight } from "./RainStreetRight";
import { Corridor } from "./Corridor";

// 雨夜河岸街明暗草图（静帧）。出图：
//   npx remotion still RainStreetRight ../../../docs/视觉设计/雨夜河岸街/发给GPT_r1/1_明暗草图_r1.png
//   npx remotion still RainStreetRight <无黄线.png> --props='{"showLines":false,"showOpenings":true}'
//   不画门窗的测试版（门窗全交给提示词）：--props='{"showLines":true,"showOpenings":false}'
//   走廊（钟楼广场往东）：npx remotion still Corridor <输出.png>
export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Still id="RainStreetRight" component={RainStreetRight} width={1672} height={941} defaultProps={{ showLines: true, showOpenings: true }} />
      <Still id="Corridor" component={Corridor} width={1672} height={941} defaultProps={{ showLines: true, showOpenings: true }} />
    </>
  );
};
