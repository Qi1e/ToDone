import { common, wantConstant } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { filePreview } from '@kit.PreviewKit';
import { isTimelineAttachmentUrl, TimelineAttachment, TimelineAttachmentKind, TimelineBlock } from '../contracts/TimelineService';

const FOLDER: string = '/timeline_attachments';
const OWN_FILE = /^attach_[a-z0-9-]+(?:\.[a-z0-9]+)?$/i;
const sessions: Map<TimelineAttachmentSession, Set<string>> = new Map<TimelineAttachmentSession, Set<string>>();
const copying: Set<string> = new Set<string>();

function keepSources(items: TimelineAttachment[] | undefined, keep: Set<string>): void {
  for (const item of items ?? []) {
    if (item.kind !== TimelineAttachmentKind.Url) keep.add(item.source);
  }
}

function unlinkIfPresent(path: string): void {
  try {
    if (fs.accessSync(path)) fs.unlinkSync(path);
  } catch (error) {
    // 下次成功读取日程后继续清理，清理失败不能影响已经保存的数据。
    console.warn('时间线附件暂未清理');
  }
}

export function cleanMatterAttachmentFiles(context: common.UIAbilityContext, referenced: TimelineAttachment[]): void {
  try {
    const dir = context.filesDir + FOLDER;
    if (!fs.accessSync(dir)) return;
    const keep = new Set<string>();
    keepSources(referenced, keep);
    sessions.forEach((sources: Set<string>) => sources.forEach((source: string) => keep.add(source)));
    for (const name of fs.listFileSync(dir)) {
      if (OWN_FILE.test(name) && !keep.has(name) && !copying.has(name)) unlinkIfPresent(dir + '/' + name);
    }
  } catch (error) {
    console.warn('事项附件清理将在下次读取后重试');
  }
}

// 仅在确认已读到存档后调用。枚举、检查与移除在同一轮事件中完成。
export function cleanTimelineAttachmentFiles(context: common.UIAbilityContext, blocks: TimelineBlock[]): void {
  try {
    const dir = context.filesDir + FOLDER;
    if (!fs.accessSync(dir)) return;
    const keep = new Set<string>();
    for (const block of blocks) {
      keepSources(block.attachments, keep);
      for (const edit of block.overrides ?? []) keepSources(edit.attachments, keep);
    }
    sessions.forEach((sources: Set<string>) => sources.forEach((source: string) => keep.add(source)));
    for (const name of fs.listFileSync(dir)) {
      if (OWN_FILE.test(name) && !keep.has(name) && !copying.has(name)) unlinkIfPresent(dir + '/' + name);
    }
  } catch (error) {
    console.warn('时间线附件清理将在下次读取后重试');
  }
}

async function selectedUri(context: common.UIAbilityContext, kind: TimelineAttachmentKind): Promise<string | undefined> {
  if (kind === TimelineAttachmentKind.Image) {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
    return selected?.photoUris?.[0];
  }
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  return (await new picker.DocumentViewPicker(context).select(options))?.[0];
}

function extension(name: string): string {
  const match = /\.[a-z0-9]{1,32}$/i.exec(name);
  return match ? match[0].toLowerCase() : '';
}

function selectedFileKind(suffix: string): TimelineAttachmentKind {
  if (suffix.length === 0) return TimelineAttachmentKind.File;
  try {
    const type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(suffix);
    const descriptor = uniformTypeDescriptor.getTypeDescriptor(type);
    if (descriptor?.belongsTo('general.audio')) return TimelineAttachmentKind.Audio;
    if (descriptor?.belongsTo('general.image')) return TimelineAttachmentKind.Image;
  } catch (error) {
    // 自定义后缀仍可作为普通文件保存。
  }
  return TimelineAttachmentKind.File;
}

export class TimelineAttachmentSession {
  private ended: boolean = false;

  isActive(): boolean {
    return !this.ended;
  }

  retain(items: TimelineAttachment[]): void {
    if (this.ended) return;
    let held = sessions.get(this);
    if (!held) {
      held = new Set<string>();
      sessions.set(this, held);
    }
    keepSources(items, held);
  }

  finish(context: common.UIAbilityContext, blocks: TimelineBlock[]): void {
    this.ended = true;
    sessions.delete(this);
    cleanTimelineAttachmentFiles(context, blocks);
  }

  finishMatter(context: common.UIAbilityContext, referenced: TimelineAttachment[]): void {
    this.ended = true;
    sessions.delete(this);
    cleanMatterAttachmentFiles(context, referenced);
  }

  async pick(context: common.UIAbilityContext, kind: TimelineAttachmentKind): Promise<TimelineAttachment | undefined> {
    if (this.ended) return undefined;
    if (kind !== TimelineAttachmentKind.Image && kind !== TimelineAttachmentKind.File) {
      throw new Error('请选择照片或文件');
    }
    let uri: string | undefined;
    try {
      uri = await selectedUri(context, kind);
    } catch (error) {
      // 某些选择器用取消异常返回；通用的权限、参数和文件错误仍应显示给用户。
      const pickerError = error as Error;
      const message = pickerError.message ?? '';
      const cancelled = /\b(?:user cancel|cancell?ed by (?:the )?user|user cancell?ed|operation cancell?ed)\b|用户(?:已)?取消/i;
      if (cancelled.test(message)) return undefined;
      throw pickerError;
    }
    if (!uri || this.ended) return undefined;
    const name = new fileUri.FileUri(uri).name;
    const dir = context.filesDir + FOLDER;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir);
    const id = 'attach_' + util.generateRandomUUID();
    const suffix = extension(name);
    const source = id + suffix;
    const destination = dir + '/' + source;
    if (fs.accessSync(destination) || copying.has(source)) throw new Error('附件文件名冲突，请重试');
    let retained = false;
    copying.add(source);
    try {
      const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      try {
        await fs.copyFile(file.fd, destination);
      } finally {
        await fs.close(file);
      }
      if (this.ended) return undefined;
      const item: TimelineAttachment = { id: id, kind: kind === TimelineAttachmentKind.File ? selectedFileKind(suffix) : kind,
        name: name, source: source };
      this.retain([item]);
      retained = true;
      return item;
    } finally {
      copying.delete(source);
      if (!retained) unlinkIfPresent(destination);
    }
  }
}

export async function openTimelineUrl(context: common.UIAbilityContext, source: string): Promise<void> {
  if (!isTimelineAttachmentUrl(source)) throw new Error('网址格式无效');
  await context.openLink(source, { appLinkingOnly: false });
}

export async function openTimelineAttachment(context: common.UIAbilityContext, item: TimelineAttachment): Promise<void> {
  if (item.kind === TimelineAttachmentKind.Url) {
    await openTimelineUrl(context, item.source);
    return;
  }
  if (!OWN_FILE.test(item.source)) throw new Error('附件位置无效');
  const path = context.filesDir + FOLDER + '/' + item.source;
  if (!fs.accessSync(path)) throw new Error('附件文件已不存在');
  const uri = fileUri.getUriFromPath(path);
  const suffix = extension(item.name);
  const type = suffix ? uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(suffix) : 'general.file';
  if (canIUse('SystemCapability.FileManagement.FilePreview.Core')) {
    try {
      if (await filePreview.canPreview(context, uri)) {
        const descriptor = uniformTypeDescriptor.getTypeDescriptor(type);
        const mime = descriptor?.mimeTypes[0] ?? 'application/octet-stream';
        await filePreview.openPreview(context, { uri: uri, title: item.name, mimeType: mime });
        return;
      }
    } catch (error) {
      console.info('系统预览不可用，尝试用兼容应用打开附件');
    }
  }
  await context.startAbility({ action: 'ohos.want.action.viewData', uri: uri, type: type,
    flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION });
}
