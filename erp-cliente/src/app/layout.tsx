import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Portal JADA",
  description: "Portal de clientes JADA",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
