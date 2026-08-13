import { getUserSubmodulos } from "@/lib/permissions";
import { SidebarNav } from "@/components/layout/SidebarNav";

export default async function ErpAppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const codigos = await getUserSubmodulos();
  const modulosVisibles = [...new Set(codigos.map((c) => c.split("_")[0]))];

  return (
    <div className="flex min-h-full flex-col lg:flex-row">
      <SidebarNav modulosVisibles={modulosVisibles} />
      <main className="flex-1 p-4 lg:p-8">{children}</main>
    </div>
  );
}
