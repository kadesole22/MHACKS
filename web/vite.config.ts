import { defineConfig } from 'vite';

// Relative asset paths let the same build work at the domain root and under /MHACKS/ on GitHub Pages.
export default defineConfig({ base: './' });
