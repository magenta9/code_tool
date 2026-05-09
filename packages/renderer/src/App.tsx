import { Navigate, Route, HashRouter, Routes } from "react-router-dom";
import { Workbench } from "./components/workbench";
import { Home } from "./routes/home";
import { SettingsPage } from "./routes/settings";
import { DiagnosticsPage } from "./routes/diagnostics";
import { JsonToolPage } from "./tools/json-tool/json-tool";
import { ImageConverterPage } from "./tools/image-converter/image-converter";
import { JsonDiffPage } from "./tools/json-diff/json-diff";
import { TimestampConverterPage } from "./tools/timestamp-converter/timestamp-converter";
import { JwtToolPage } from "./tools/jwt-tool/jwt-tool";
import { WordCloudPage } from "./tools/word-cloud/word-cloud";
import { AiChatPage } from "./tools/ai-chat/ai-chat";
import { AiSpeechPage } from "./tools/ai-speech/ai-speech";
import { AiImagePage } from "./tools/ai-image/ai-image";
import { AiMusicPage } from "./tools/ai-music/ai-music";

export function App(): JSX.Element {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Workbench />}>
          <Route index element={<Home />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="diagnostics" element={<DiagnosticsPage />} />
          <Route path="tools/json" element={<JsonToolPage />} />
          <Route path="tools/image-converter" element={<ImageConverterPage />} />
          <Route path="tools/json-diff" element={<JsonDiffPage />} />
          <Route path="tools/timestamp" element={<TimestampConverterPage />} />
          <Route path="tools/jwt" element={<JwtToolPage />} />
          <Route path="tools/word-cloud" element={<WordCloudPage />} />
          <Route path="tools/ai-chat" element={<AiChatPage />} />
          <Route path="tools/ai-speech" element={<AiSpeechPage />} />
          <Route path="tools/ai-image" element={<AiImagePage />} />
          <Route path="tools/ai-music" element={<AiMusicPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </HashRouter>
  );
}
