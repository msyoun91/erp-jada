import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // `next dev` solo confía en `localhost`: desde el celular, por la IP de LAN,
  // el runtime de Turbopack nunca arrancaba y la página quedaba en HTML muerto
  // — el form de login hacía submit nativo en vez de correr el handler.
  // El match es por hostname y por segmentos, así que el comodín aguanta que
  // DHCP cambie el último octeto.
  allowedDevOrigins: ["192.168.1.*"],
};

export default nextConfig;
