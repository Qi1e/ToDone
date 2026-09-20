interface ColorTokens {
  page: string;
  surface: string;
  surfaceSoft: string;
  text: string;
  subText: string;
  border: string;
  primary: string;
  primarySoft: string;
  success: string;
  warning: string;
  danger: string;
}

interface RadiusTokens {
  small: number;
  normal: number;
  large: number;
}

interface SpaceTokens {
  tiny: number;
  small: number;
  normal: number;
  large: number;
  section: number;
}

export const Colors: ColorTokens = {
  page: '#F7F9FC',
  surface: '#FFFFFF',
  surfaceSoft: '#EEF4FF',
  text: '#101828',
  subText: '#667085',
  border: '#E4EAF2',
  primary: '#2F7BFF',
  primarySoft: '#DDEBFF',
  success: '#00A88B',
  warning: '#FF8A3D',
  danger: '#E5486D'
};

export const Radius: RadiusTokens = {
  small: 8,
  normal: 12,
  large: 18
};

export const Space: SpaceTokens = {
  tiny: 4,
  small: 8,
  normal: 12,
  large: 16,
  section: 24
};
