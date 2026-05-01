// Icon glyphs — SF-Symbols-inspired but original line drawings
// All take size and color props. Stroke-based, 1.5pt nominal weight.

const Icon = ({ name, size = 14, color = 'currentColor', style = {} }) => {
  const sz = size;
  const s = { width: sz, height: sz, display: 'inline-block', verticalAlign: 'middle', flexShrink: 0, ...style };
  const sw = Math.max(1.2, sz / 12);
  const common = { width: sz, height: sz, viewBox: '0 0 16 16', fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round', style: s };

  switch (name) {
    case 'chevron-left':  return <svg {...common}><path d="M10 3 L5 8 L10 13" /></svg>;
    case 'chevron-right': return <svg {...common}><path d="M6 3 L11 8 L6 13" /></svg>;
    case 'chevron-up':    return <svg {...common}><path d="M3 10 L8 5 L13 10" /></svg>;
    case 'chevron-down':  return <svg {...common}><path d="M3 6 L8 11 L13 6" /></svg>;
    case 'magnifying':    return <svg {...common}><circle cx="7" cy="7" r="4.2" /><path d="M10.2 10.2 L13.5 13.5" /></svg>;
    case 'plus':          return <svg {...common}><path d="M8 3 V13 M3 8 H13" /></svg>;
    case 'xmark':         return <svg {...common}><path d="M4 4 L12 12 M12 4 L4 12" /></svg>;
    case 'sidebar-left':  return <svg {...common}><rect x="2" y="3.5" width="12" height="9" rx="1.5" /><path d="M6.5 3.5 V12.5" /></svg>;
    case 'sidebar-right': return <svg {...common}><rect x="2" y="3.5" width="12" height="9" rx="1.5" /><path d="M9.5 3.5 V12.5" /></svg>;
    case 'square':        return <svg {...common}><rect x="3" y="3" width="10" height="10" rx="1.2" /></svg>;
    case 'split-2x1':     return <svg {...common}><rect x="3" y="3" width="10" height="10" rx="1.2" /><path d="M8 3 V13" /></svg>;
    case 'split-1x2':     return <svg {...common}><rect x="3" y="3" width="10" height="10" rx="1.2" /><path d="M3 8 H13" /></svg>;
    case 'split-2x2':     return <svg {...common}><rect x="3" y="3" width="10" height="10" rx="1.2" /><path d="M8 3 V13 M3 8 H13" /></svg>;
    case 'arrow-down-circle': return <svg {...common}><circle cx="8" cy="8" r="5.2" /><path d="M8 5.2 V10.5 M5.5 8 L8 10.6 L10.5 8" /></svg>;
    case 'eject':         return <svg {...common}><path d="M3.5 9.5 L8 4 L12.5 9.5 Z" /><path d="M3.5 12 H12.5" /></svg>;
    case 'circle-fill':   return <svg width={sz} height={sz} viewBox="0 0 16 16" style={s}><circle cx="8" cy="8" r="4.5" fill={color} /></svg>;
    case 'gear':          return <svg {...common}><circle cx="8" cy="8" r="2" /><path d="M8 1.5 V3.5 M8 12.5 V14.5 M1.5 8 H3.5 M12.5 8 H14.5 M3.3 3.3 L4.7 4.7 M11.3 11.3 L12.7 12.7 M3.3 12.7 L4.7 11.3 M11.3 4.7 L12.7 3.3" /></svg>;
    case 'info':          return <svg {...common}><circle cx="8" cy="8" r="5.5" /><path d="M8 7 V11 M8 5 V5.01" /></svg>;
    case 'play-fill':     return <svg width={sz} height={sz} viewBox="0 0 16 16" style={s}><path d="M5 3.5 L12 8 L5 12.5 Z" fill={color} /></svg>;
    case 'minus':         return <svg {...common}><path d="M3 8 H13" /></svg>;
    default: return null;
  }
};

// File-type icon: small colored rectangle with corner fold + label, matching macOS document feel
const FileIcon = ({ node, size = 16 }) => {
  if (node.type === 'folder') {
    return (
      <svg width={size} height={size} viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
        <defs>
          <linearGradient id={`fld-${node.id}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#7fbcff" />
            <stop offset="1" stopColor="#3a8fe6" />
          </linearGradient>
        </defs>
        <path d="M1.5 5 Q1.5 4 2.5 4 H6.2 L7.4 5.2 H13.5 Q14.5 5.2 14.5 6.2 V12 Q14.5 13 13.5 13 H2.5 Q1.5 13 1.5 12 Z" fill={`url(#fld-${node.id})`} />
        <path d="M1.5 5 Q1.5 4 2.5 4 H6.2 L7.4 5.2 H13.5 Q14.5 5.2 14.5 6.2 V6.5 H1.5 Z" fill="#5aa3f0" opacity="0.35" />
      </svg>
    );
  }
  // file — color-coded by kind
  const kind = node.kind;
  const ext = node.name.includes('.') ? node.name.split('.').pop().toUpperCase() : '';
  let bg = '#3a3a3c', label = ext.slice(0, 4), labelColor = '#fff';
  if (/Swift/i.test(kind)) { bg = '#fa7343'; label = 'SW'; }
  else if (/PDF/i.test(kind)) { bg = '#e8453c'; label = 'PDF'; }
  else if (/PNG|JPEG|HEIC|Image/i.test(kind)) { bg = '#5aa3f0'; label = 'IMG'; }
  else if (/Movie|MPEG/i.test(kind)) { bg = '#bf5af2'; label = 'MOV'; }
  else if (/WAV|Audio|Ableton/i.test(kind)) { bg = '#ff9f0a'; label = 'AUD'; }
  else if (/Markdown/i.test(kind)) { bg = '#3a3a3c'; label = 'MD'; }
  else if (/Plain Text|Rich Text|CSV/i.test(kind)) { bg = '#48484a'; label = 'TXT'; }
  else if (/Word/i.test(kind)) { bg = '#2b6dd0'; label = 'DOC'; }
  else if (/Numbers/i.test(kind)) { bg = '#32d74b'; label = 'NUM'; }
  else if (/ZIP|XIP|Archive|Disk Image|Installer/i.test(kind)) { bg = '#8e8e93'; label = 'ZIP'; }
  else if (/Application/i.test(kind)) { bg = '#0a84ff'; label = 'APP'; }
  else if (/Font/i.test(kind)) { bg = '#5e5ce6'; label = 'FNT'; }
  else if (/Asset/i.test(kind)) { bg = '#0a84ff'; label = 'AST'; }
  else if (/Property|Shell|Document/i.test(kind)) { bg = '#48484a'; label = ext.slice(0,3) || 'TXT'; }

  const fontSize = label.length >= 4 ? 3.4 : 4.0;
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
      <path d="M3 1.5 H10 L13 4.5 V14 Q13 14.5 12.5 14.5 H3.5 Q3 14.5 3 14 Z" fill={bg} />
      <path d="M10 1.5 V4 Q10 4.5 10.5 4.5 H13" fill="none" stroke="rgba(255,255,255,0.4)" strokeWidth="0.5" />
      <path d="M10 1.5 L13 4.5 H10.5 Q10 4.5 10 4 Z" fill="rgba(255,255,255,0.18)" />
      <text x="8" y="11.4" fontSize={fontSize} fontFamily="-apple-system, system-ui, sans-serif" fontWeight="700" fill={labelColor} textAnchor="middle" letterSpacing="0">{label}</text>
    </svg>
  );
};

// Sidebar item icons — small monochrome glyphs
const SidebarIcon = ({ name, size = 14, color = '#0a84ff' }) => {
  const common = { width: size, height: size, viewBox: '0 0 16 16', fill: 'none', stroke: color, strokeWidth: 1.3, strokeLinecap: 'round', strokeLinejoin: 'round', style: { flexShrink: 0 } };
  switch (name) {
    case 'desktop':   return <svg {...common}><rect x="2" y="3" width="12" height="8" rx="1" /><path d="M6 13 H10 M8 11 V13" /></svg>;
    case 'docs':      return <svg {...common}><path d="M4 2 H10 L12 4 V14 H4 Z" /><path d="M10 2 V4 H12" /></svg>;
    case 'downloads': return <svg {...common}><path d="M8 2 V11 M5 8 L8 11 L11 8" /><path d="M3 13 H13" /></svg>;
    case 'pictures':  return <svg {...common}><rect x="2" y="3" width="12" height="10" rx="1" /><circle cx="6" cy="7" r="1.2" /><path d="M2 11 L6 8 L10 11 L14 8" /></svg>;
    case 'movies':    return <svg {...common}><rect x="2" y="3" width="12" height="10" rx="1" /><path d="M5 3 V13 M11 3 V13 M2 6.5 H5 M11 6.5 H14 M2 9.5 H5 M11 9.5 H14" /></svg>;
    case 'projects':  return <svg {...common}><path d="M2 5 H6 L7.5 6.5 H14 V13 H2 Z" /><path d="M2 5 V3.5 H5.5 L7 5" /></svg>;
    case 'home':      return <svg {...common}><path d="M2.5 8 L8 3 L13.5 8 V13 H10 V9 H6 V13 H2.5 Z" /></svg>;
    case 'volume':    return <svg {...common}><rect x="2" y="4" width="12" height="8" rx="1" /><circle cx="11.5" cy="8" r="0.5" fill={color} /></svg>;
    case 'icloud':    return <svg {...common}><path d="M4 11 Q1.5 11 1.5 8.5 Q1.5 6.5 3.5 6.2 Q4 4 6.5 4 Q9 4 9.5 6.2 Q12.5 6.2 12.5 8.5 Q12.5 11 10 11 Z" /></svg>;
    default: return null;
  }
};

Object.assign(window, { Icon, FileIcon, SidebarIcon });
