import type { ReactNode } from "react";

import "./styles.css";

export const metadata = {
  title: "Event Driven Commerce",
  description: "Phase 1a order entry",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
