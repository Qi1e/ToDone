export type ClusterRole = 'cluster.pine' | 'cluster.wisteria' | 'cluster.kerria' | 'cluster.indigo' | 'cluster.ink';

interface ColorTokens {
  bg: Resource;
  card: Resource;
  ink: Resource;
  inkSoft: Resource;
  inkMuted: Resource;
  hairline: Resource;
  line: Resource;
  track: Resource;
  wash: Resource;
  dash: Resource;
  dragShadow: Resource;
  red: Resource;
  redPressed: Resource;
  onRed: Resource;
}

interface RadiusTokens {
  chip: number;
  card: number;
}

interface SpaceTokens {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  page: number;
  section: number;
  xl: number;
}

interface TypeSizeTokens {
  display: number;
  heading: number;
  title: number;
  body: number;
  bodySmall: number;
  meta: number;
  figure: number;
}

interface TypeWeightTokens {
  regular: number;
  semibold: number;
}

interface MotionTokens {
  duration: number;
}

export const Colors: ColorTokens = {
  bg: $r('app.color.paper_bg'),
  card: $r('app.color.paper_card'),
  ink: $r('app.color.paper_ink'),
  inkSoft: $r('app.color.paper_ink_soft'),
  inkMuted: $r('app.color.paper_ink_muted'),
  hairline: $r('app.color.paper_hairline'),
  line: $r('app.color.paper_line'),
  track: $r('app.color.paper_track'),
  wash: $r('app.color.paper_wash'),
  dash: $r('app.color.paper_dash'),
  dragShadow: $r('app.color.paper_drag_shadow'),
  red: $r('app.color.accent_red'),
  redPressed: $r('app.color.accent_red_pressed'),
  onRed: $r('app.color.accent_on')
};

export const Radius: RadiusTokens = {
  chip: 3,
  card: 4
};

export const Space: SpaceTokens = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  page: 20,
  section: 24,
  xl: 32
};

export const TypeSize: TypeSizeTokens = {
  display: 30,
  heading: 24,
  title: 16,
  body: 14,
  bodySmall: 13,
  meta: 12,
  figure: 24
};

export const TypeWeight: TypeWeightTokens = {
  regular: 400,
  semibold: 600
};

export const Motion: MotionTokens = {
  duration: 160
};

export const TABULAR_NUMS: string = '"tnum" 1';

export function resolveClusterRole(raw?: string): ClusterRole | undefined {
  if (!raw) {
    return undefined;
  }
  const normalized = raw.trim().toUpperCase();
  if (normalized.length === 0 || normalized === '#D8DEE8') {
    return undefined;
  }
  if (normalized === 'CLUSTER.PINE' || normalized === '#2F7BFF' || normalized === '#2E6E62' || normalized === '#8BBFAF') {
    return 'cluster.pine';
  }
  if (normalized === 'CLUSTER.WISTERIA' || normalized === '#00A88B' || normalized === '#6A5C8C' || normalized === '#B3A2D4') {
    return 'cluster.wisteria';
  }
  if (normalized === 'CLUSTER.KERRIA' || normalized === '#FF8A3D' || normalized === '#B9822C' || normalized === '#DDB26A') {
    return 'cluster.kerria';
  }
  if (normalized === 'CLUSTER.INDIGO' || normalized === '#9B6CFF' || normalized === '#3B5F86' || normalized === '#93AFCF') {
    return 'cluster.indigo';
  }
  if (normalized === 'CLUSTER.INK' || normalized === '#E5486D' || normalized === '#23211C' || normalized === '#EFE9DC') {
    return 'cluster.ink';
  }
  return 'cluster.pine';
}

export function clusterColorResource(role: ClusterRole): Resource {
  switch (role) {
    case 'cluster.pine':
      return $r('app.color.cluster_pine');
    case 'cluster.wisteria':
      return $r('app.color.cluster_wisteria');
    case 'cluster.kerria':
      return $r('app.color.cluster_kerria');
    case 'cluster.indigo':
      return $r('app.color.cluster_indigo');
    case 'cluster.ink':
      return $r('app.color.cluster_ink');
  }
}

export function clusterTintResource(role: ClusterRole): Resource {
  switch (role) {
    case 'cluster.pine':
      return $r('app.color.cluster_pine_tint');
    case 'cluster.wisteria':
      return $r('app.color.cluster_wisteria_tint');
    case 'cluster.kerria':
      return $r('app.color.cluster_kerria_tint');
    case 'cluster.indigo':
      return $r('app.color.cluster_indigo_tint');
    case 'cluster.ink':
      return $r('app.color.cluster_ink_tint');
  }
}

export function resolveClusterColor(raw?: string): Resource | undefined {
  const role = resolveClusterRole(raw);
  return role ? clusterColorResource(role) : undefined;
}

export function resolveClusterTint(raw?: string): Resource {
  const role = resolveClusterRole(raw) ?? 'cluster.pine';
  return clusterTintResource(role);
}
