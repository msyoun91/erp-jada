import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Portal JADA",
  description: "Portal de clientes JADA",
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
        {/* <script> plano y no <Script beforeInteractive>: esa estrategia encola en self.__next_s
            y la vacía un chunk async, o sea después del primer paint — flash de tema claro. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
        {children}
      </body>
    </html>
  );
}
