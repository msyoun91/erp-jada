import { Sidebar } from "@/components/layout/Sidebar";

export default async function ErpAppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-col md:flex-row">
      {/* Al imprimir (el impreso de Presupuestos) sale solo la página. */}
      <div className="contents print:hidden">
        <Sidebar />
      </div>
      <main className="mx-auto w-full max-w-[1280px] flex-1 p-4 lg:p-8 print:max-w-none print:p-0">{children}</main>
    </div>
  );
}
