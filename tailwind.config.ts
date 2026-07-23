import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Brand palette taken from the cookbook page spreads.
        brand: {
          pink: "#E11D6B",
          "pink-dark": "#C21458",
          purple: "#7C3AED",
          "purple-dark": "#5B21B6",
          cream: "#FCE9CC",
          ink: "#1A1524",
        },
      },
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
      },
      maxWidth: {
        content: "72rem",
      },
    },
  },
  plugins: [],
};

export default config;
