import { Contact } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { puedeAuditar, puedeVerContactos } from "@/modules/contactos/permissions";

// Auditoría es una vista aparte: el auditor no necesita ver la agenda.
export default async function ContactosLayout({ children }: { children: React.ReactNode }) {
  const [ver, auditar] = await Promise.all([puedeVerContactos(), puedeAuditar()]);
  const tabs = [
    ...(ver
      ? [
          { codigo: "contactos_personas", label: "Personas", href: "/contactos" },
          { codigo: "contactos_empresas", label: "Empresas", href: "/contactos/empresas" },
        ]
      : []),
    ...(auditar ? [{ codigo: "contactos_auditoria", label: "Auditoría", href: "/contactos/auditoria" }] : []),
  ];

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="contactos" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Contact size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Contactos
      </h1>
      <ModuleTabs modulo="contactos" tabs={tabs} />
      {children}
    </div>
  );
}
