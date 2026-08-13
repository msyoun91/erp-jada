import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { getUserSubmodulos } from "@/lib/permissions";
import { SidebarNav } from "./SidebarNav";
import { MobileNav } from "./MobileNav";

export async function Sidebar() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [codigos, { data: usuario }] = await Promise.all([
    getUserSubmodulos(),
    supabase.from("usuarios").select("nombre").eq("id", user.id).single(),
  ]);

  const modulosVisibles = [...new Set(codigos.map((c) => c.split("_")[0]))];
  const nombre = usuario?.nombre ?? user.email ?? "";

  return (
    <>
      <aside className="hidden w-[220px] shrink-0 flex-col border-r border-border bg-bg-nav p-3 lg:sticky lg:top-0 lg:flex lg:h-screen">
        <Image src="/logo.svg" alt="JADA" width={72} height={26} className="logo mb-4 ml-1" priority />
        <SidebarNav modulosVisibles={modulosVisibles} nombre={nombre} />
      </aside>
      <MobileNav modulosVisibles={modulosVisibles} nombre={nombre} />
    </>
  );
}
