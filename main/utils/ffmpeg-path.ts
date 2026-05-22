import ffmpeg from 'ffmpeg-static';
import util from 'electron-util';

if (!ffmpeg) {
  throw new Error('ffmpeg-static did not resolve a binary path');
}

const ffmpegPath = util.fixPathForAsarUnpack(ffmpeg);

export default ffmpegPath;
