import type { Metadata } from "next";
import Script from "next/script";
import { Toaster } from "sonner";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import "./globals.css";

export const metadata: Metadata = {
  title: "ERP JADA",
  description: "Sistema de gestión JADA",
};

const THEME_INIT_SCRIPT = `
(function () {
  try {
    var t = localStorage.getItem("jada-theme");
    if (!t) t = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    document.documentElement.setAttribute("data-theme", t);
  } catch (e) {}
})();
`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased" suppressHydrationWarning>
      <body className="min-h-full flex flex-col">
        <Script
          id="theme-init"
          strategy="beforeInteractive"
          dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }}
        />
        {children}
        <ThemeToggle />
        {/* En mobile el toaster ocupa el ancho completo y el topbar mide 56px: sin offset lo tapa. */}
        <Toaster position="top-right" richColors mobileOffset={{ top: "72px" }} />
      </body>
    </html>
  );
}
