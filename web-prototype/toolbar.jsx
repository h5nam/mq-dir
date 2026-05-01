// Toolbar — traffic lights, nav buttons, breadcrumb, search, layout switcher

const TrafficLight = ({ color, hover }) => (
  <div style={{ width: 12, height: 12, borderRadius: '50%', background: color, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.2)' }} />
);

const TrafficLights = () => {
  const [hover, setHover] = React.useState(false);
  return (
    <div onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)} style={{ display: 'flex', gap: 8, alignItems: 'center', paddingLeft: 12, paddingRight: 4 }}>
      <TrafficLight color="#ff5f57" hover={hover} />
      <TrafficLight color="#febc2e" hover={hover} />
      <TrafficLight color="#28c840" hover={hover} />
    </div>
  );
};

const ToolButton = ({ children, onClick, disabled, title, active }) => {
  const [hover, setHover] = React.useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      disabled={disabled}
      title={title}
      style={{
        height: 22,
        minWidth: 26,
        padding: '0 6px',
        background: active ? 'rgba(255,255,255,0.1)' : (hover && !disabled ? 'rgba(255,255,255,0.06)' : 'transparent'),
        border: 'none',
        borderRadius: 4,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        cursor: 'default',
        color: disabled ? 'var(--label-tertiary)' : 'var(--label-secondary)',
      }}
    >
      {children}
    </button>
  );
};

const SegmentedLayout = ({ value, onChange }) => {
  const segs = [
    { v: 1, icon: 'square' },
    { v: 2, icon: 'split-2x1' },
    { v: 3, icon: 'split-1x2' },
    { v: 4, icon: 'split-2x2' },
  ];
  return (
    <div style={{ display: 'flex', height: 22, background: 'rgba(255,255,255,0.05)', borderRadius: 5, padding: 1.5, gap: 0 }}>
      {segs.map(s => {
        const active = value === s.v;
        return (
          <button
            key={s.v}
            onClick={() => onChange(s.v)}
            title={`${s.v} pane${s.v > 1 ? 's' : ''}`}
            style={{
              width: 26,
              height: 19,
              background: active ? 'rgba(255,255,255,0.12)' : 'transparent',
              border: 'none',
              borderRadius: 3.5,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'default',
              boxShadow: active ? '0 0.5px 0 0 rgba(255,255,255,0.08)' : 'none',
            }}
          >
            <Icon name={s.icon} size={12} color={active ? 'var(--label)' : 'var(--label-secondary)'} />
          </button>
        );
      })}
    </div>
  );
};

const Breadcrumb = ({ path, onNavigate, loading }) => {
  const parts = splitPath(path);
  const segs = [{ name: 'Macintosh HD', path: '/' }];
  let acc = '';
  parts.forEach(p => { acc += '/' + p; segs.push({ name: p, path: acc }); });
  // show only last 4 segments to avoid overflow
  const visible = segs.length > 4 ? [segs[0], { name: '…', ellipsis: true }, ...segs.slice(-3)] : segs;

  return (
    <div style={{
      flex: 1,
      height: 22,
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      padding: '0 8px',
      background: 'rgba(0,0,0,0.18)',
      border: '0.5px solid rgba(255,255,255,0.06)',
      borderRadius: 5,
      fontSize: 12,
      color: 'var(--label)',
      overflow: 'hidden',
      minWidth: 0,
    }}>
      {visible.map((s, i) => (
        <React.Fragment key={i}>
          {i > 0 && <Icon name="chevron-right" size={9} color="var(--label-tertiary)" />}
          <span
            onClick={() => !s.ellipsis && onNavigate(s.path)}
            style={{
              padding: '1px 4px',
              borderRadius: 3,
              cursor: 'default',
              color: i === visible.length - 1 ? 'var(--label)' : 'var(--label-secondary)',
              fontWeight: i === visible.length - 1 ? 500 : 400,
              whiteSpace: 'nowrap',
            }}
          >
            {s.name === 'hona' ? <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}><SidebarIcon name="home" size={11} color="var(--label-secondary)" />hona</span> : s.name}
          </span>
        </React.Fragment>
      ))}
    </div>
  );
};

const Toolbar = ({ paneCount, onChangePaneCount, focusedPath, onNavigate, onBack, onForward, onUp, canBack, canForward, sidebarVisible, onToggleSidebar, previewVisible, onTogglePreview }) => {
  return (
    <div style={{
      height: 32,
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: '0 10px 0 0',
      background: 'var(--toolbar-bg)',
      borderBottom: '1px solid var(--separator)',
      WebkitAppRegion: 'drag',
    }}>
      <TrafficLights />
      <div style={{ width: 4 }} />
      <ToolButton onClick={onToggleSidebar} title="Toggle Sidebar" active={sidebarVisible}>
        <Icon name="sidebar-left" size={14} color="var(--label-secondary)" />
      </ToolButton>
      <div style={{ width: 4 }} />
      <ToolButton onClick={onBack} disabled={!canBack} title="Back">
        <Icon name="chevron-left" size={13} color={canBack ? 'var(--label-secondary)' : 'var(--label-tertiary)'} />
      </ToolButton>
      <ToolButton onClick={onForward} disabled={!canForward} title="Forward">
        <Icon name="chevron-right" size={13} color={canForward ? 'var(--label-secondary)' : 'var(--label-tertiary)'} />
      </ToolButton>
      <ToolButton onClick={onUp} title="Parent folder">
        <Icon name="chevron-up" size={13} color="var(--label-secondary)" />
      </ToolButton>
      <div style={{ width: 4 }} />
      <Breadcrumb path={focusedPath} onNavigate={onNavigate} />
      <div style={{
        height: 22,
        width: 140,
        display: 'flex',
        alignItems: 'center',
        gap: 4,
        padding: '0 8px',
        background: 'rgba(0,0,0,0.18)',
        border: '0.5px solid rgba(255,255,255,0.06)',
        borderRadius: 5,
        fontSize: 12,
      }}>
        <Icon name="magnifying" size={11} color="var(--label-tertiary)" />
        <span style={{ color: 'var(--label-tertiary)' }}>Search</span>
      </div>
      <ToolButton onClick={onTogglePreview} title="Toggle Preview" active={previewVisible}>
        <Icon name="sidebar-right" size={14} color="var(--label-secondary)" />
      </ToolButton>
      <SegmentedLayout value={paneCount} onChange={onChangePaneCount} />
    </div>
  );
};

Object.assign(window, { Toolbar });
