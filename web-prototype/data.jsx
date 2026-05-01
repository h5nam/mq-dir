// Fake filesystem — rich home directory tree
// Each node: { id, name, type: 'folder'|'file', kind, size, modified, children?, hidden?, icloud?, mediaType? }

const FS = (() => {
  let nextId = 1;
  const id = () => `n${nextId++}`;

  const file = (name, kind, size, modified, extras = {}) => ({
    id: id(), name, type: 'file', kind, size, modified, ...extras,
  });
  const folder = (name, modified, children = [], extras = {}) => ({
    id: id(), name, type: 'folder', kind: 'Folder', size: null, modified, children, ...extras,
  });

  const root = {
    id: id(), name: '/', type: 'folder', kind: 'Folder', children: [
      folder('Users', 'Mar 12 2026', [
        folder('hona', 'Today 14:22', [
          folder('Desktop', 'Today 11:04', [
            file('todo.txt', 'Plain Text', 1_240, 'Today 11:04'),
            file('.zshrc', 'Shell Script', 2_408, 'Apr 24 09:22', { hidden: true }),
            file('wallpaper-coast.png', 'PNG Image', 8_421_000, 'Apr 18 19:30', { mediaType: 'image' }),
            file('screenshot 2026-04-30 at 3.42.png', 'PNG Image', 412_000, 'Apr 30 15:42', { mediaType: 'image' }),
          ]),
          folder('Documents', 'Today 09:30', [
            folder('Contracts', 'Apr 22 14:00', [
              file('msa-acme-2026.pdf', 'PDF Document', 482_000, 'Apr 22 14:00'),
              file('sow-q2.pdf', 'PDF Document', 218_000, 'Apr 18 10:30'),
              file('nda-template.docx', 'Word Document', 38_000, 'Mar 02 17:00'),
            ]),
            folder('Finance', 'Apr 29 18:11', [
              file('budget-2026.numbers', 'Numbers Spreadsheet', 102_400, 'Apr 29 18:11'),
              file('expenses-april.csv', 'CSV', 12_300, 'Apr 30 09:00'),
              file('invoice-0042.pdf', 'PDF Document', 320_000, 'Apr 29 18:45'),
            ]),
            file('report-q1.docx', 'Word Document', 44_000, 'Today 09:30'),
            file('notes-draft.md', 'Markdown', 12_400, 'Apr 26 11:00'),
            file('reading-list.rtf', 'Rich Text', 8_200, 'Apr 14 22:10'),
            file('passport-scan.pdf', 'PDF Document', 2_100_000, 'Apr 26 12:30', { icloud: true }),
            file('lease-2026.pdf', 'PDF Document', 1_800_000, 'Mar 11 10:00', { icloud: true }),
          ]),
          folder('Downloads', 'Today 14:22', [
            file('project-notes.txt', 'Plain Text', 4_096, 'Today 14:22'),
            file('screenshot-2026.png', 'PNG Image', 2_100_000, 'Today 09:11', { mediaType: 'image' }),
            file('invoice.pdf', 'PDF Document', 320_000, 'Apr 29 18:45'),
            file('archive.zip', 'ZIP Archive', 15_300_000, 'Apr 28 10:00'),
            file('video-demo.mov', 'QuickTime Movie', 234_000_000, 'Apr 27 16:30', { mediaType: 'video' }),
            file('Xcode_15.4.xip', 'XIP Archive', 7_200_000_000, 'Apr 19 22:01'),
            file('homebrew-installer.pkg', 'Installer Package', 12_400_000, 'Apr 12 08:30'),
            file('ableton-live-12.dmg', 'Disk Image', 2_900_000_000, 'Apr 09 19:50'),
            file('font-pack.zip', 'ZIP Archive', 88_000_000, 'Apr 02 11:11'),
            file('.DS_Store', 'Document', 6_148, 'Apr 24 08:00', { hidden: true }),
          ]),
          folder('Pictures', 'Today 09:22', [
            folder('Screenshots', 'Today 16:01', [
              file('CleanShot 2026-04-30 at 16.01.png', 'PNG Image', 612_000, 'Today 16:01', { mediaType: 'image' }),
              file('CleanShot 2026-04-29 at 09.40.png', 'PNG Image', 488_000, 'Apr 29 09:40', { mediaType: 'image' }),
              file('CleanShot 2026-04-28 at 18.22.png', 'PNG Image', 720_000, 'Apr 28 18:22', { mediaType: 'image' }),
            ]),
            folder('Camera Roll', 'Apr 27 16:30', [
              file('IMG_0423.heic', 'HEIC Image', 3_800_000, 'Today 09:22', { mediaType: 'image' }),
              file('IMG_0422.heic', 'HEIC Image', 4_100_000, 'Today 08:14', { mediaType: 'image' }),
              file('IMG_0421.jpg', 'JPEG Image', 2_200_000, 'Apr 29 19:01', { mediaType: 'image' }),
              file('IMG_0420.heic', 'HEIC Image', 3_200_000, 'Apr 27 16:30', { mediaType: 'image', icloud: true }),
              file('vacation.mov', 'QuickTime Movie', 812_000_000, 'Apr 28 11:00', { mediaType: 'video' }),
              file('birthday.heic', 'HEIC Image', 3_200_000, 'Apr 27 16:30', { mediaType: 'image' }),
            ]),
            file('cover-photo.jpg', 'JPEG Image', 2_400_000, 'Apr 14 10:00', { mediaType: 'image' }),
          ]),
          folder('Projects', 'Today 13:55', [
            folder('mq-dir', 'Today 13:55', [
              folder('.git', 'Today 13:55', [
                file('HEAD', 'Document', 23, 'Today 13:55', { hidden: true }),
                file('config', 'Document', 312, 'Today 13:55', { hidden: true }),
              ], { hidden: true }),
              folder('Sources', 'Today 13:50', [
                file('App.swift', 'Swift Source', 4_200, 'Today 13:50'),
                file('WindowViewModel.swift', 'Swift Source', 18_400, 'Today 13:48'),
                file('PaneView.swift', 'Swift Source', 22_100, 'Today 13:42'),
                file('FileListView.swift', 'Swift Source', 31_200, 'Today 13:30'),
                file('Sidebar.swift', 'Swift Source', 9_800, 'Apr 30 22:00'),
                file('PreviewPane.swift', 'Swift Source', 14_400, 'Apr 30 21:45'),
              ]),
              folder('Resources', 'Apr 28 10:00', [
                file('Assets.xcassets', 'Asset Catalog', 248_000, 'Apr 28 10:00'),
                file('Info.plist', 'Property List', 2_800, 'Apr 28 10:00'),
              ]),
              file('Package.swift', 'Swift Source', 1_400, 'Apr 30 12:00'),
              file('README.md', 'Markdown', 8_900, 'Today 11:30'),
              file('LICENSE', 'Document', 1_100, 'Mar 11 08:00'),
            ]),
            folder('side-quests', 'Apr 22 19:00', [
              folder('audio-toy', 'Apr 22 19:00', [
                file('main.swift', 'Swift Source', 4_800, 'Apr 22 19:00'),
                file('synth.swift', 'Swift Source', 12_300, 'Apr 22 18:30'),
              ]),
              folder('terminal-fonts', 'Apr 14 10:00', [
                file('berkeley-mono.otf', 'OpenType Font', 412_000, 'Apr 14 10:00'),
                file('iosevka.ttf', 'TrueType Font', 2_100_000, 'Apr 14 09:55'),
              ]),
            ]),
          ]),
          folder('Movies', 'Apr 18 11:00', [
            file('demo-reel.mp4', 'MPEG-4 Movie', 488_000_000, 'Apr 18 11:00', { mediaType: 'video' }),
            file('interview-cut.mov', 'QuickTime Movie', 2_400_000_000, 'Apr 12 14:00', { mediaType: 'video' }),
          ]),
          folder('Music', 'Mar 30 22:00', [
            folder('Live Sets', 'Mar 30 22:00', [
              file('boiler-room-2024.als', 'Ableton Project', 18_400_000, 'Mar 30 22:00'),
            ]),
            file('demo-track.wav', 'WAV Audio', 88_000_000, 'Mar 28 19:00'),
          ]),
          file('.bash_profile', 'Shell Script', 1_200, 'Mar 02 14:00', { hidden: true }),
          file('.gitconfig', 'Document', 480, 'Apr 14 09:00', { hidden: true }),
        ]),
      ]),
      folder('Applications', 'Apr 18 22:00', [
        file('Xcode.app', 'Application', 12_400_000_000, 'Apr 18 22:00'),
        file('Safari.app', 'Application', 88_000_000, 'Apr 18 22:00'),
        file('Terminal.app', 'Application', 12_000_000, 'Apr 18 22:00'),
        file('Iina.app', 'Application', 88_000_000, 'Apr 18 22:00'),
      ]),
      folder('Volumes', 'Apr 30 12:00', [
        folder('USB Drive', 'Apr 30 12:00', [
          file('backup-2026-04.zip', 'ZIP Archive', 8_400_000_000, 'Apr 30 12:00'),
          file('photos-export.zip', 'ZIP Archive', 12_400_000_000, 'Apr 22 14:00'),
        ]),
      ]),
    ],
  };

  // Build path-keyed lookup
  const byPath = new Map();
  const walk = (node, path) => {
    const p = path === '/' ? `/${node.name}` : `${path}/${node.name}`;
    const fullPath = node.name === '/' ? '/' : p;
    byPath.set(fullPath, node);
    node.path = fullPath;
    if (node.children) node.children.forEach(c => walk(c, fullPath));
  };
  walk(root, '');

  return { root, byPath };
})();

const FAVORITES = [
  { name: 'Desktop',   path: '/Users/hona/Desktop',   icon: 'desktop' },
  { name: 'Documents', path: '/Users/hona/Documents', icon: 'docs' },
  { name: 'Downloads', path: '/Users/hona/Downloads', icon: 'downloads' },
  { name: 'Pictures',  path: '/Users/hona/Pictures',  icon: 'pictures' },
  { name: 'Movies',    path: '/Users/hona/Movies',    icon: 'movies' },
  { name: 'Projects',  path: '/Users/hona/Projects',  icon: 'projects' },
  { name: 'hona',      path: '/Users/hona',           icon: 'home' },
];

const VOLUMES = [
  { name: 'Macintosh HD', path: '/',                       icon: 'volume', removable: false },
  { name: 'USB Drive',    path: '/Volumes/USB Drive',      icon: 'volume', removable: true },
  { name: 'iCloud Drive', path: '/Users/hona/Documents',   icon: 'icloud', removable: false },
];

const TAGS = [
  { name: 'Red',     color: '#ff453a' },
  { name: 'Orange',  color: '#ff9f0a' },
  { name: 'Yellow',  color: '#ffd60a' },
  { name: 'Green',   color: '#32d74b' },
  { name: 'Blue',    color: '#0a84ff' },
  { name: 'Purple',  color: '#bf5af2' },
  { name: 'Gray',    color: '#8e8e93' },
];

// Format helpers
const fmtSize = (bytes) => {
  if (bytes == null) return '--';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024*1024)).toFixed(1)} MB`;
  if (bytes < 1024 * 1024 * 1024 * 1024) return `${(bytes / (1024*1024*1024)).toFixed(1)} GB`;
  return `${(bytes / (1024*1024*1024*1024)).toFixed(2)} TB`;
};

const getNodeAtPath = (path) => FS.byPath.get(path);

const getChildren = (path, showHidden = false) => {
  const node = getNodeAtPath(path);
  if (!node || !node.children) return [];
  return showHidden ? node.children : node.children.filter(c => !c.hidden);
};

const splitPath = (path) => {
  if (path === '/') return [];
  return path.split('/').filter(Boolean);
};

const parentPath = (path) => {
  if (path === '/' || !path) return '/';
  const parts = splitPath(path);
  if (parts.length <= 1) return '/';
  return '/' + parts.slice(0, -1).join('/');
};

Object.assign(window, { FS, FAVORITES, VOLUMES, TAGS, fmtSize, getNodeAtPath, getChildren, splitPath, parentPath });
