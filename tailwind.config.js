/** Token desain dari prototipe: netral + aksen emas, status berwarna lembut. */
export default {
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
      colors: {
        ink: '#111827',
        muted: '#5B6270',
        surface: '#F5F5F7',
        line: '#E8E8EC',
        gold: { DEFAULT: '#D9A441', dark: '#8A6212' },
        ok: { bg: '#E7F6EC', fg: '#1B6B3A' },
        warn: { bg: '#FFF1DB', fg: '#8A5200' },
        info: { bg: '#E6F0FB', fg: '#1F5A99' },
        bad: { bg: '#FDE8E8', fg: '#A12A2A' },
      },
      borderRadius: { xl: '16px', '2xl': '24px' },
    },
  },
  plugins: [],
}
