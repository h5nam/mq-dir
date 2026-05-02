import SwiftUI

// Maps a FileEntry to a (SF Symbol name, accent color) pair, matching the
// Claude Design prototype's color-coded file rows. Folders, swift, pdf,
// image, video, audio, archive, doc, and text each get distinct hues.

enum FileIconStyle {
    static func symbol(for entry: FileEntry) -> String {
        if entry.isDirectory {
            return "folder.fill"
        }

        switch entry.url.pathExtension.lowercased() {
        case "swift", "h", "m", "c", "cpp", "rs", "go", "py", "js", "ts", "tsx", "jsx":
            return "doc.text.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp", "webp":
            return "photo.fill"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            return "play.rectangle.fill"
        case "mp3", "m4a", "aac", "wav", "flac", "ogg":
            return "waveform"
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg":
            return "doc.zipper"
        case "doc", "docx", "pages":
            return "doc.fill"
        case "xls", "xlsx", "numbers":
            return "tablecells.fill"
        case "key", "ppt", "pptx":
            return "rectangle.stack.fill"
        default:
            return "doc"
        }
    }

    static func tint(for entry: FileEntry) -> Color {
        if entry.isDirectory {
            return Color(red: 0x4f/255, green: 0xa3/255, blue: 0xff/255)
        }

        switch entry.url.pathExtension.lowercased() {
        case "swift":
            return Color(red: 0xfa/255, green: 0x73/255, blue: 0x43/255)
        case "h", "m", "c", "cpp":
            return Color(red: 0x6c/255, green: 0x9a/255, blue: 0xff/255)
        case "rs", "go", "py", "js", "ts", "tsx", "jsx":
            return Color(red: 0x9c/255, green: 0xa6/255, blue: 0xff/255)
        case "pdf":
            return Color(red: 0xe8/255, green: 0x45/255, blue: 0x3c/255)
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp", "webp":
            return Color(red: 0x5a/255, green: 0xa3/255, blue: 0xf0/255)
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            return Color(red: 0xbf/255, green: 0x5a/255, blue: 0xf2/255)
        case "mp3", "m4a", "aac", "wav", "flac", "ogg":
            return Color(red: 0xff/255, green: 0x9f/255, blue: 0x0a/255)
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg":
            return Color(red: 0x8e/255, green: 0x8e/255, blue: 0x93/255)
        case "doc", "docx", "pages":
            return Color(red: 0x2b/255, green: 0x6d/255, blue: 0xd0/255)
        case "xls", "xlsx", "numbers":
            return Color(red: 0x32/255, green: 0xd7/255, blue: 0x4b/255)
        case "key", "ppt", "pptx":
            return Color(red: 0xff/255, green: 0x9f/255, blue: 0x0a/255)
        default:
            return Theme.Color.labelSecondary
        }
    }
}
