export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      usuarios: {
        Row: {
          id: string;
          nombre: string;
          email: string;
          activo: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          nombre: string;
          email: string;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          nombre?: string;
          email?: string;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      submodulos: {
        Row: {
          id: string;
          codigo: string;
          modulo: string;
          tipo: Database["public"]["Enums"]["tipo_submodulo"];
          nombre: string;
          orden: number;
          activo: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          codigo: string;
          modulo: string;
          tipo: Database["public"]["Enums"]["tipo_submodulo"];
          nombre: string;
          orden?: number;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          codigo?: string;
          modulo?: string;
          tipo?: Database["public"]["Enums"]["tipo_submodulo"];
          nombre?: string;
          orden?: number;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      usuario_submodulos: {
        Row: {
          id: string;
          usuario_id: string;
          submodulo_id: string;
          activo: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          usuario_id: string;
          submodulo_id: string;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          usuario_id?: string;
          submodulo_id?: string;
          activo?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey";
            columns: ["submodulo_id"];
            isOneToOne: false;
            referencedRelation: "submodulos";
            referencedColumns: ["id"];
          }
        ];
      };
    };
    Views: Record<string, never>;
    Functions: {
      tiene_permiso: {
        Args: { p_codigo: string };
        Returns: boolean;
      };
    };
    Enums: {
      tipo_submodulo: "seccion" | "funcion";
    };
    CompositeTypes: Record<string, never>;
  };
};
