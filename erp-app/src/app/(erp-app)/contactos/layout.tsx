import { Contact } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";

// Una sola vista (`contactos_ver`) con dos pestañas; Auditoría entra con su tramo.
const tabs = [
  { codigo: "contactos_personas", label: "Personas", href: "/contactos" },
  { codigo: "contactos_empresas", label: "Empresas", href: "/contactos/empresas" },
];

export default function ContactosLayout({ children }: { children: React.ReactNode }) {
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
