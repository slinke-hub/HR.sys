const os = require('node:os');
const nativeUserInfo = os.userInfo;

os.userInfo = (...args) => {
  try {
    return nativeUserInfo(...args);
  } catch {
    return {
      uid: -1,
      gid: -1,
      username: process.env.USERNAME || 'user',
      homedir: process.env.USERPROFILE || process.cwd(),
      shell: process.env.COMSPEC || 'cmd.exe'
    };
  }
};
