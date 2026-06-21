import "./styles.css";
import type { ReactNode } from "react";

export const metadata = {
  title: "Event Driven Commerce",
  description: "Phase 1a order request path",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
