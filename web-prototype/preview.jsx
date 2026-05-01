// Preview pane — image or video QuickLook-style

const PreviewPane = ({ node, onClose }) => {
  const [zoom, setZoom] = React.useState(100);
  React.useEffect(() => { setZoom(100); }, [node.id]);

  const isVideo = node.mediaType === 'video';
  const isImage = node.mediaType === 'image';

  // Generate placeholder image content based on file name
  const seed = node.name.length;
  const hue1 = (seed * 37) % 360;
  const hue2 = (hue1 + 60) % 360;

  return (
    <div style={{
      width: 320,
      borderLeft: '1px solid var(--separator)',
      background: 'var(--preview-bg)',
      display: 'flex',
      flexDirection: 'column',
      flexShrink: 0,
    }}>
      {/* Preview header */}
      <div style={{ height: 22, padding: '0 10px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: '1px solid var(--separator-faint)', fontSize: 11, fontWeight: 500, color: 'var(--label-secondary)', textTransform: 'uppercase', letterSpacing: 0.4 }}>
        <span>Preview</span>
        <span onClick={onClose} style={{ cursor: 'default', display: 'flex', padding: 2 }} title="Close preview">
          <Icon name="xmark" size={9} color="var(--label-secondary)" />
        </span>
      </div>

      {/* Preview content */}
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', padding: 16, background: '#000' }}>
        {isImage && (
          <div style={{
            width: `${zoom}%`,
            maxWidth: '100%',
            aspectRatio: '4 / 3',
            background: `linear-gradient(135deg, hsl(${hue1}, 60%, 45%), hsl(${hue2}, 70%, 35%))`,
            borderRadius: 2,
            boxShadow: '0 4px 16px rgba(0,0,0,0.5)',
            display: 'flex',
            alignItems: 'flex-end',
            padding: 12,
            position: 'relative',
            overflow: 'hidden',
          }}>
            {/* placeholder visual elements */}
            <div style={{ position: 'absolute', top: '20%', left: '15%', width: '30%', height: '40%', background: `hsla(${hue2}, 80%, 70%, 0.5)`, borderRadius: '50%', filter: 'blur(20px)' }} />
            <div style={{ position: 'absolute', top: '40%', right: '10%', width: '25%', height: '30%', background: `hsla(${hue1}, 80%, 80%, 0.4)`, borderRadius: '50%', filter: 'blur(16px)' }} />
            <div style={{ position: 'relative', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 10, color: 'rgba(255,255,255,0.6)', textShadow: '0 1px 2px rgba(0,0,0,0.5)' }}>
              {node.name}
            </div>
          </div>
        )}
        {isVideo && (
          <div style={{
            width: '100%',
            aspectRatio: '16 / 9',
            background: `linear-gradient(180deg, #1a1a1c 0%, #0a0a0c 100%)`,
            borderRadius: 2,
            position: 'relative',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            overflow: 'hidden',
          }}>
            <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 40%, hsla(${hue1}, 50%, 30%, 0.6), transparent 60%)` }} />
            <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'rgba(255,255,255,0.85)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 12px rgba(0,0,0,0.4)' }}>
              <Icon name="play-fill" size={20} color="#000" style={{ marginLeft: 3 }} />
            </div>
            {/* QL chrome */}
            <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 28, background: 'linear-gradient(180deg, transparent, rgba(0,0,0,0.6))', display: 'flex', alignItems: 'center', padding: '0 10px', gap: 8 }}>
              <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.85)', fontVariantNumeric: 'tabular-nums' }}>0:00</div>
              <div style={{ flex: 1, height: 3, background: 'rgba(255,255,255,0.2)', borderRadius: 1.5, position: 'relative' }}>
                <div style={{ width: '0%', height: '100%', background: '#fff', borderRadius: 1.5 }} />
              </div>
              <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums' }}>{node.mediaType === 'video' ? formatDuration(node.size) : '0:00'}</div>
            </div>
          </div>
        )}
      </div>

      {/* zoom controls (image only) */}
      {isImage && (
        <div style={{ height: 28, borderTop: '1px solid var(--separator-faint)', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, fontSize: 11, color: 'var(--label-secondary)' }}>
          <button onClick={() => setZoom(Math.max(25, zoom - 25))} style={ctrlBtn}><Icon name="minus" size={10} color="var(--label-secondary)" /></button>
          <span style={{ fontVariantNumeric: 'tabular-nums', minWidth: 36, textAlign: 'center' }}>{zoom}%</span>
          <button onClick={() => setZoom(Math.min(400, zoom + 25))} style={ctrlBtn}><Icon name="plus" size={10} color="var(--label-secondary)" /></button>
        </div>
      )}

      {/* Metadata */}
      <div style={{ borderTop: '1px solid var(--separator-faint)', padding: 12, fontSize: 11, color: 'var(--label-secondary)', display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{ color: 'var(--label)', fontSize: 12, fontWeight: 500, marginBottom: 4, wordBreak: 'break-word' }}>{node.name}</div>
        <Meta label="Kind" value={node.kind} />
        <Meta label="Size" value={node.icloud ? '--' : fmtSize(node.size)} />
        <Meta label="Modified" value={node.modified} />
        {isImage && <Meta label="Dimensions" value="4032 x 3024" />}
        {isVideo && <Meta label="Duration" value={formatDuration(node.size)} />}
      </div>
    </div>
  );
};

const Meta = ({ label, value }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
    <span style={{ color: 'var(--label-tertiary)' }}>{label}</span>
    <span style={{ color: 'var(--label-secondary)', fontVariantNumeric: 'tabular-nums' }}>{value}</span>
  </div>
);

const formatDuration = (size) => {
  const sec = Math.min(7200, Math.max(8, Math.floor((size || 100_000_000) / 4_000_000)));
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
};

const ctrlBtn = {
  width: 22, height: 18,
  background: 'transparent',
  border: 'none',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  cursor: 'default',
  borderRadius: 3,
};

Object.assign(window, { PreviewPane });
