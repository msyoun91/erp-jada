import { Sidebar } from "@/components/layout/Sidebar";

export default async function ErpAppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-col lg:flex-row">
      <Sidebar />
      <main className="flex-1 p-4 lg:p-8">{children}</main>
    </div>
  );
}
