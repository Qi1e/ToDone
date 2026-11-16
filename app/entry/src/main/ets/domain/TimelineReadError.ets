interface SystemReadError extends Error {
  code?: number;
}

// 仅对外提供读取阶段、记录序号与系统数字错误码。解析异常的 message 可能含有日程原文。
export function timelineReadCode(error: Error, stage: string): string {
  if (error && typeof error.message === 'string' &&
    /^TL-(?:OPEN|READ|JSON|FORMAT|VERSION|TAG|BLOCK|RANGE|OVERRIDE|TAGREF|DUPLICATE)(?:[:#]-?\d+)?$/.test(error.message)) {
    return error.message;
  }
  const code = (error as SystemReadError)?.code;
  return 'TL-' + stage + (typeof code === 'number' && Number.isSafeInteger(code) ? ':' + code : '');
}
