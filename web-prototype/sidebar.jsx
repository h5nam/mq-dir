// Sidebar — favorites, volumes, tags

const SidebarSection = ({ title, children, addable }) => (
  <div style={{ marginBottom: 14 }}>
    <div style={{
      padding: '0 12px',
      height: 18,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      fontSize: 11,
      fontWeight: 700,
      color: 'var(--label-tertiary)',
      letterSpacing: 0.5,
      textTransform: 'uppercase',
      marginBottom: 2,
    }}>
      <span>{title}</span>
    </div>
    {children}
  </div>
);

const SidebarItem = ({ icon, color, name, active, onClick, removable, count, indent = 0 }) => {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        height: 24,
        display: 'flex',
        alignItems: 'center',
        gap: 7,
        padding: `0 12px 0 ${12 + indent}px`,
        marginLeft: 4,
        marginRight: 4,
        borderRadius: 5,
        background: active ? 'var(--sidebar-selection)' : (hover ? 'rgba(255,255,255,0.04)' : 'transparent'),
        color: 'var(--label)',
        fontSize: 13,
        cursor: 'default',
        userSelect: 'none',
      }}
    >
      {typeof icon === 'string' ? <SidebarIcon name={icon} size={14} color={color || 'var(--accent)'} /> : icon}
      <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
      {removable && hover && <Icon name="eject" size={11} color="var(--label-secondary)" />}
      {count != null && <span style={{ fontSize: 11, color: 'var(--label-tertiary)' }}>{count}</span>}
    </div>
  );
};

const Sidebar = ({ width, currentPath, onNavigate }) => {
  return (
    <div style={{
      width,
      flexShrink: 0,
      background: 'var(--sidebar-bg)',
      borderRight: '1px solid var(--separator)',
      paddingTop: 10,
      paddingBottom: 10,
      overflow: 'auto',
      display: 'flex',
      flexDirection: 'column',
    }}>
      <SidebarSection title="Favorites">
        {FAVORITES.map(f => (
          <SidebarItem key={f.path} icon={f.icon} name={f.name} active={currentPath === f.path} onClick={() => onNavigate(f.path)} />
        ))}
      </SidebarSection>

      <SidebarSection title="Locations">
        {VOLUMES.map(v => (
          <SidebarItem key={v.path + v.name} icon={v.icon} name={v.name} active={currentPath === v.path && v.name !== 'iCloud Drive'} onClick={() => onNavigate(v.path)} removable={v.removable} />
        ))}
      </SidebarSection>

      <SidebarSection title="Tags">
        {TAGS.map(t => (
          <SidebarItem
            key={t.name}
            icon={<span style={{ width: 10, height: 10, borderRadius: '50%', background: t.color, display: 'inline-block', flexShrink: 0, marginLeft: 2 }} />}
            name={t.name}
            onClick={() => {}}
          />
        ))}
      </SidebarSection>
    </div>
  );
};

Object.assign(window, { Sidebar });
