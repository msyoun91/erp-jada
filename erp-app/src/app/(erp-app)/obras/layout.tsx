import { Building2 } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { puedeVerObras, puedeVerTodas } from "@/modules/obras/permissions";

export default async function ObrasLayout({ children }: { children: React.ReactNode }) {
  const [ver, verTodas] = await Promise.all([puedeVerObras(), puedeVerTodas()]);
  const tabs = [
    ...(ver ? [{ codigo: "obras_ver", label: "Obras", href: "/obras" }] : []),
    ...(verTodas ? [{ codigo: "obras_todas", label: "Todas", href: "/obras/todas" }] : []),
  ];

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="obras" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Building2 size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Obras
      </h1>
      <ModuleTabs modulo="obras" tabs={tabs} />
      {children}
    </div>
  );
}
