import { UsersRound } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";

const tabs = [{ codigo: "usuarios_ver", label: "Usuarios", href: "/usuarios" }];

export default function UsuariosLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="usuarios" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <UsersRound size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Usuarios
      </h1>
      <ModuleTabs modulo="usuarios" tabs={tabs} />
      {children}
    </div>
  );
}
