-- =============================================================================
-- Smart Community RT — Skema Database
-- =============================================================================
--
-- PostgreSQL database dump
--


-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: tolak_ubah_activity_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tolak_ubah_activity_logs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        RAISE EXCEPTION
          'activity_logs bersifat hanya-tambah: % ditolak. Jejak audit tidak boleh diubah atau dihapus.',
          TG_OP
          USING ERRCODE = 'insufficient_privilege';
      END;
      $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_logs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    user_nama character varying(255),
    user_role character varying(100),
    tipe character varying(50) NOT NULL,
    aktivitas text NOT NULL,
    ip_address character varying(45),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: agenda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda (
    id integer NOT NULL,
    judul character varying(255) NOT NULL,
    deskripsi text,
    tipe character varying(50) DEFAULT 'Kegiatan'::character varying,
    tanggal date NOT NULL,
    waktu_mulai time without time zone,
    waktu_selesai time without time zone,
    lokasi character varying(255),
    status character varying(50) DEFAULT 'Akan Datang'::character varying,
    notulen_url character varying(500),
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamp without time zone
);


--
-- Name: agenda_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agenda_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agenda_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agenda_id_seq OWNED BY public.agenda.id;


--
-- Name: alokasi_bop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alokasi_bop (
    id integer NOT NULL,
    tahun integer NOT NULL,
    termin character varying(30) DEFAULT 'Tahunan'::character varying NOT NULL,
    nominal numeric NOT NULL,
    sumber_dana character varying(100),
    keterangan text,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: alokasi_bop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.alokasi_bop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: alokasi_bop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.alokasi_bop_id_seq OWNED BY public.alokasi_bop.id;


--
-- Name: anggota_keluarga; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anggota_keluarga (
    id integer NOT NULL,
    keluarga_id integer,
    nik character varying(16),
    nama character varying(255) NOT NULL,
    jenis_kelamin character varying(1),
    tempat_lahir character varying(100),
    tanggal_lahir date,
    agama character varying(50),
    status_keluarga character varying(50),
    pekerjaan character varying(100),
    pendidikan character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    has_ktp boolean DEFAULT true,
    domisili character varying(50) DEFAULT 'Tetap'::character varying,
    is_aktif boolean DEFAULT true,
    status_pernikahan character varying(50),
    no_hp character varying(20),
    CONSTRAINT anggota_keluarga_jenis_kelamin_check CHECK (((jenis_kelamin)::text = ANY ((ARRAY['L'::character varying, 'P'::character varying])::text[])))
);


--
-- Name: anggota_keluarga_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.anggota_keluarga_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: anggota_keluarga_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.anggota_keluarga_id_seq OWNED BY public.anggota_keluarga.id;


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcements (
    id integer NOT NULL,
    judul character varying(255) NOT NULL,
    isi text NOT NULL,
    kategori character varying(50) DEFAULT 'Umum'::character varying,
    status character varying(20) DEFAULT 'draft'::character varying,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: announcements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.announcements_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: announcements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.announcements_id_seq OWNED BY public.announcements.id;


--
-- Name: bantuan_sosial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bantuan_sosial (
    id integer NOT NULL,
    user_id uuid,
    jenis_bantuan character varying(100) NOT NULL,
    bentuk_bantuan character varying(50) DEFAULT 'Tunai'::character varying,
    sumber_bantuan character varying(100) DEFAULT 'Pemerintah Pusat'::character varying,
    no_sk character varying(100),
    tanggal_bantuan date,
    tanggal_mulai date,
    tanggal_selesai date,
    tahun integer,
    nominal numeric DEFAULT 0,
    status character varying(20) DEFAULT 'Aktif'::character varying,
    keterangan text,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: bantuan_sosial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bantuan_sosial_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bantuan_sosial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bantuan_sosial_id_seq OWNED BY public.bantuan_sosial.id;


--
-- Name: bantuan_sosial_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bantuan_sosial_log (
    id integer NOT NULL,
    bantuan_sosial_id integer,
    changed_by uuid,
    old_status character varying(50),
    new_status character varying(50),
    keterangan_log text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: bantuan_sosial_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bantuan_sosial_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bantuan_sosial_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bantuan_sosial_log_id_seq OWNED BY public.bantuan_sosial_log.id;


--
-- Name: bill_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_payments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    bill_id uuid,
    user_id uuid,
    jumlah_bayar numeric NOT NULL,
    metode_bayar character varying(50) NOT NULL,
    invoice_number character varying(100) NOT NULL,
    paid_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bills (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    jenis_tagihan character varying(50) NOT NULL,
    bulan character varying(7) NOT NULL,
    nominal numeric NOT NULL,
    keterangan text,
    status character varying(20) DEFAULT 'unpaid'::character varying,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    keluarga_id integer,
    jenis_iuran_id integer,
    jatuh_tempo date,
    meteran_lalu integer,
    meteran_sekarang integer,
    tarif_per_m3 integer,
    abondement integer,
    biaya_sampah integer,
    langganan_sampah boolean,
    CONSTRAINT bills_meteran_maju CHECK (((meteran_lalu IS NULL) OR (meteran_sekarang IS NULL) OR (meteran_sekarang >= meteran_lalu)))
);


--
-- Name: bop_finances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bop_finances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tipe character varying(20) NOT NULL,
    jumlah numeric NOT NULL,
    deskripsi text,
    tanggal date DEFAULT CURRENT_DATE,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    kategori character varying(50) DEFAULT 'Umum'::character varying,
    kategori_id integer,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: borrowings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.borrowings (
    id integer NOT NULL,
    inventory_id integer,
    user_id uuid,
    jumlah integer DEFAULT 1,
    tanggal_pinjam date DEFAULT CURRENT_DATE,
    tanggal_kembali date,
    status character varying(20) DEFAULT 'Dipinjam'::character varying,
    keterangan text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    tanggal_rencana_kembali date,
    dicatat_oleh uuid,
    nama_peminjam character varying(255),
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: borrowings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.borrowings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: borrowings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.borrowings_id_seq OWNED BY public.borrowings.id;


--
-- Name: complaints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.complaints (
    id integer NOT NULL,
    kode_tiket character varying(20) NOT NULL,
    user_id uuid,
    judul character varying(255) NOT NULL,
    deskripsi text,
    kategori character varying(100),
    status character varying(50) DEFAULT 'Menunggu'::character varying,
    response text,
    responded_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamp without time zone
);


--
-- Name: complaints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.complaints_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: complaints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.complaints_id_seq OWNED BY public.complaints.id;


--
-- Name: emergency_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emergency_alerts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    message text,
    latitude numeric,
    longitude numeric,
    status character varying(20) DEFAULT 'active'::character varying,
    dismissed_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dismissed_at timestamp without time zone
);


--
-- Name: finances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tipe character varying(20) NOT NULL,
    kategori character varying(50) NOT NULL,
    jumlah numeric NOT NULL,
    deskripsi text,
    tanggal date DEFAULT CURRENT_DATE,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    kategori_id integer,
    sumber character varying(20) DEFAULT 'manual'::character varying,
    ref_id uuid,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamp without time zone
);


--
-- Name: inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory (
    id integer NOT NULL,
    nama_barang character varying(255) NOT NULL,
    kategori character varying(100),
    jumlah integer DEFAULT 0,
    kondisi character varying(50) DEFAULT 'Baik'::character varying,
    lokasi character varying(255),
    keterangan text,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    nilai_barang numeric DEFAULT 0,
    tanggal_perolehan date,
    deleted_at timestamp without time zone
);


--
-- Name: inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_id_seq OWNED BY public.inventory.id;


--
-- Name: jenis_iuran; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jenis_iuran (
    id integer NOT NULL,
    nama_iuran character varying(100) NOT NULL,
    nominal_default numeric DEFAULT 0,
    periode character varying(20) DEFAULT 'bulanan'::character varying,
    is_aktif boolean DEFAULT true,
    keterangan text,
    tipe_hitung character varying(20) DEFAULT 'tetap'::character varying NOT NULL,
    tarif_per_m3 integer,
    abondement integer DEFAULT 0 NOT NULL,
    biaya_sampah integer DEFAULT 0 NOT NULL,
    CONSTRAINT jenis_iuran_tipe_hitung_sah CHECK (((tipe_hitung)::text = ANY ((ARRAY['tetap'::character varying, 'meteran'::character varying])::text[])))
);


--
-- Name: jenis_iuran_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jenis_iuran_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jenis_iuran_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jenis_iuran_id_seq OWNED BY public.jenis_iuran.id;


--
-- Name: kategori_bop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kategori_bop (
    id integer NOT NULL,
    nama_kategori character varying(100) NOT NULL,
    tipe character varying(3) NOT NULL,
    is_aktif boolean DEFAULT true,
    keterangan text,
    CONSTRAINT kategori_bop_tipe_check CHECK (((tipe)::text = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying])::text[])))
);


--
-- Name: kategori_bop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kategori_bop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kategori_bop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kategori_bop_id_seq OWNED BY public.kategori_bop.id;


--
-- Name: kategori_kas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kategori_kas (
    id integer NOT NULL,
    nama_kategori character varying(100) NOT NULL,
    tipe character varying(3) NOT NULL,
    is_aktif boolean DEFAULT true,
    keterangan text,
    CONSTRAINT kategori_kas_tipe_check CHECK (((tipe)::text = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying])::text[])))
);


--
-- Name: kategori_kas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kategori_kas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kategori_kas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kategori_kas_id_seq OWNED BY public.kategori_kas.id;


--
-- Name: keluarga; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.keluarga (
    id integer NOT NULL,
    no_kk character varying(16) NOT NULL,
    kepala_keluarga character varying(255) NOT NULL,
    alamat text,
    rt character varying(3) DEFAULT '001'::character varying,
    rw character varying(3) DEFAULT '001'::character varying,
    kelurahan character varying(100),
    kecamatan character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status_rumah character varying(50) DEFAULT 'Milik Sendiri'::character varying,
    deleted_at timestamp without time zone,
    blok character varying(20),
    langganan_sampah boolean DEFAULT true NOT NULL
);


--
-- Name: keluarga_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.keluarga_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: keluarga_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.keluarga_id_seq OWNED BY public.keluarga.id;


--
-- Name: letters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.letters (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    jenis_surat character varying(100) NOT NULL,
    keperluan text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying,
    approved_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    response_note text,
    tanggal_respon timestamp without time zone,
    deleted_at timestamp without time zone
);


--
-- Name: menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_items (
    id integer NOT NULL,
    kode character varying(60) NOT NULL,
    nama character varying(100) NOT NULL,
    grup character varying(50),
    menu_index integer,
    urutan integer DEFAULT 0,
    is_aktif boolean DEFAULT true,
    is_sistem boolean DEFAULT false
);


--
-- Name: menu_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.menu_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: menu_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.menu_items_id_seq OWNED BY public.menu_items.id;


--
-- Name: payment_transaction_bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_transaction_bills (
    transaction_id uuid NOT NULL,
    bill_id uuid NOT NULL,
    nominal numeric NOT NULL,
    is_pending boolean DEFAULT true NOT NULL
);


--
-- Name: payment_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_transactions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_id character varying(64) NOT NULL,
    user_id uuid,
    keluarga_id integer,
    gross_amount numeric NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    snap_token character varying(255),
    redirect_url text,
    payment_type character varying(50),
    midtrans_payload jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    settled_at timestamp without time zone
);


--
-- Name: pembacaan_meteran; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pembacaan_meteran (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    keluarga_id integer NOT NULL,
    periode character varying(7) NOT NULL,
    meteran_lalu integer,
    meteran_sekarang integer,
    status character varying(20) DEFAULT 'menunggu'::character varying NOT NULL,
    catatan text,
    diisi_oleh uuid,
    diisi_pada timestamp without time zone,
    dikoreksi_oleh uuid,
    dikoreksi_pada timestamp without time zone,
    bill_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pembacaan_meteran_status_sah CHECK (((status)::text = ANY ((ARRAY['menunggu'::character varying, 'terisi'::character varying, 'anomali'::character varying])::text[])))
);


--
-- Name: polling; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.polling (
    id integer NOT NULL,
    judul character varying(255) NOT NULL,
    deskripsi text,
    status character varying(20) DEFAULT 'aktif'::character varying,
    tanggal_mulai date NOT NULL,
    tanggal_selesai date NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: polling_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.polling_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: polling_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.polling_id_seq OWNED BY public.polling.id;


--
-- Name: polling_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.polling_options (
    id integer NOT NULL,
    polling_id integer,
    label character varying(255) NOT NULL,
    vote_count integer DEFAULT 0
);


--
-- Name: polling_options_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.polling_options_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: polling_options_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.polling_options_id_seq OWNED BY public.polling_options.id;


--
-- Name: polling_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.polling_votes (
    id integer NOT NULL,
    polling_id integer,
    option_id integer,
    user_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: polling_votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.polling_votes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: polling_votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.polling_votes_id_seq OWNED BY public.polling_votes.id;


--
-- Name: reset_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reset_logs (
    id integer NOT NULL,
    grup_kode character varying(60) NOT NULL,
    grup_nama character varying(100) NOT NULL,
    rincian jsonb NOT NULL,
    total_baris integer DEFAULT 0 NOT NULL,
    dicadangkan boolean DEFAULT false,
    user_id uuid,
    user_nama character varying(100),
    user_role character varying(30),
    ip_address character varying(45),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: reset_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reset_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reset_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reset_logs_id_seq OWNED BY public.reset_logs.id;


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    id integer NOT NULL,
    role character varying(30) NOT NULL,
    menu_kode character varying(60) NOT NULL,
    can_view boolean DEFAULT false,
    can_create boolean DEFAULT false,
    can_update boolean DEFAULT false,
    can_delete boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: role_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.role_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.role_permissions_id_seq OWNED BY public.role_permissions.id;


--
-- Name: sensor_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sensor_logs (
    id integer NOT NULL,
    sensor_type character varying(50) NOT NULL,
    value numeric NOT NULL,
    unit character varying(20),
    "timestamp" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: sensor_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sensor_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensor_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sensor_logs_id_seq OWNED BY public.sensor_logs.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    username character varying(100),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    nama character varying(255),
    email character varying(255),
    password_hash character varying(255),
    no_hp character varying(20),
    no_kk character varying(16),
    alamat text,
    no_rt character varying(3) DEFAULT '001'::character varying,
    role character varying(50) DEFAULT 'warga'::character varying,
    nik character varying(16),
    deleted_at timestamp without time zone,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    must_change_password boolean DEFAULT false NOT NULL
);


--
-- Name: visitors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.visitors (
    id integer NOT NULL,
    nama_tamu character varying(255) NOT NULL,
    no_hp_tamu character varying(20),
    blok_tujuan character varying(100),
    no_hp_tujuan character varying(20),
    tipe_keperluan character varying(50) DEFAULT 'Kunjungan'::character varying,
    detail_keperluan text,
    plat_nomor character varying(20),
    jenis_kendaraan character varying(50),
    jam_masuk timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    jam_keluar timestamp without time zone,
    status character varying(20) DEFAULT 'Di Dalam'::character varying,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: visitors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.visitors_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: visitors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.visitors_id_seq OWNED BY public.visitors.id;


--
-- Name: agenda id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda ALTER COLUMN id SET DEFAULT nextval('public.agenda_id_seq'::regclass);


--
-- Name: alokasi_bop id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alokasi_bop ALTER COLUMN id SET DEFAULT nextval('public.alokasi_bop_id_seq'::regclass);


--
-- Name: anggota_keluarga id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anggota_keluarga ALTER COLUMN id SET DEFAULT nextval('public.anggota_keluarga_id_seq'::regclass);


--
-- Name: announcements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements ALTER COLUMN id SET DEFAULT nextval('public.announcements_id_seq'::regclass);


--
-- Name: bantuan_sosial id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial ALTER COLUMN id SET DEFAULT nextval('public.bantuan_sosial_id_seq'::regclass);


--
-- Name: bantuan_sosial_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial_log ALTER COLUMN id SET DEFAULT nextval('public.bantuan_sosial_log_id_seq'::regclass);


--
-- Name: borrowings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.borrowings ALTER COLUMN id SET DEFAULT nextval('public.borrowings_id_seq'::regclass);


--
-- Name: complaints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints ALTER COLUMN id SET DEFAULT nextval('public.complaints_id_seq'::regclass);


--
-- Name: inventory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory ALTER COLUMN id SET DEFAULT nextval('public.inventory_id_seq'::regclass);


--
-- Name: jenis_iuran id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jenis_iuran ALTER COLUMN id SET DEFAULT nextval('public.jenis_iuran_id_seq'::regclass);


--
-- Name: kategori_bop id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_bop ALTER COLUMN id SET DEFAULT nextval('public.kategori_bop_id_seq'::regclass);


--
-- Name: kategori_kas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_kas ALTER COLUMN id SET DEFAULT nextval('public.kategori_kas_id_seq'::regclass);


--
-- Name: keluarga id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keluarga ALTER COLUMN id SET DEFAULT nextval('public.keluarga_id_seq'::regclass);


--
-- Name: menu_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items ALTER COLUMN id SET DEFAULT nextval('public.menu_items_id_seq'::regclass);


--
-- Name: polling id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling ALTER COLUMN id SET DEFAULT nextval('public.polling_id_seq'::regclass);


--
-- Name: polling_options id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_options ALTER COLUMN id SET DEFAULT nextval('public.polling_options_id_seq'::regclass);


--
-- Name: polling_votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes ALTER COLUMN id SET DEFAULT nextval('public.polling_votes_id_seq'::regclass);


--
-- Name: reset_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reset_logs ALTER COLUMN id SET DEFAULT nextval('public.reset_logs_id_seq'::regclass);


--
-- Name: role_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions ALTER COLUMN id SET DEFAULT nextval('public.role_permissions_id_seq'::regclass);


--
-- Name: sensor_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_logs ALTER COLUMN id SET DEFAULT nextval('public.sensor_logs_id_seq'::regclass);


--
-- Name: visitors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitors ALTER COLUMN id SET DEFAULT nextval('public.visitors_id_seq'::regclass);


--
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (id);


--
-- Name: agenda agenda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda
    ADD CONSTRAINT agenda_pkey PRIMARY KEY (id);


--
-- Name: alokasi_bop alokasi_bop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alokasi_bop
    ADD CONSTRAINT alokasi_bop_pkey PRIMARY KEY (id);


--
-- Name: alokasi_bop alokasi_bop_tahun_termin_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alokasi_bop
    ADD CONSTRAINT alokasi_bop_tahun_termin_key UNIQUE (tahun, termin);


--
-- Name: anggota_keluarga anggota_keluarga_nik_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anggota_keluarga
    ADD CONSTRAINT anggota_keluarga_nik_key UNIQUE (nik);


--
-- Name: anggota_keluarga anggota_keluarga_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anggota_keluarga
    ADD CONSTRAINT anggota_keluarga_pkey PRIMARY KEY (id);


--
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: bantuan_sosial_log bantuan_sosial_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial_log
    ADD CONSTRAINT bantuan_sosial_log_pkey PRIMARY KEY (id);


--
-- Name: bantuan_sosial bantuan_sosial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial
    ADD CONSTRAINT bantuan_sosial_pkey PRIMARY KEY (id);


--
-- Name: bill_payments bill_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT bill_payments_pkey PRIMARY KEY (id);


--
-- Name: bills bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_pkey PRIMARY KEY (id);


--
-- Name: bop_finances bop_finances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bop_finances
    ADD CONSTRAINT bop_finances_pkey PRIMARY KEY (id);


--
-- Name: borrowings borrowings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.borrowings
    ADD CONSTRAINT borrowings_pkey PRIMARY KEY (id);


--
-- Name: complaints complaints_kode_tiket_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_kode_tiket_key UNIQUE (kode_tiket);


--
-- Name: complaints complaints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_pkey PRIMARY KEY (id);


--
-- Name: emergency_alerts emergency_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_alerts
    ADD CONSTRAINT emergency_alerts_pkey PRIMARY KEY (id);


--
-- Name: finances finances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finances
    ADD CONSTRAINT finances_pkey PRIMARY KEY (id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (id);


--
-- Name: jenis_iuran jenis_iuran_nama_iuran_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jenis_iuran
    ADD CONSTRAINT jenis_iuran_nama_iuran_key UNIQUE (nama_iuran);


--
-- Name: jenis_iuran jenis_iuran_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jenis_iuran
    ADD CONSTRAINT jenis_iuran_pkey PRIMARY KEY (id);


--
-- Name: kategori_bop kategori_bop_nama_kategori_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_bop
    ADD CONSTRAINT kategori_bop_nama_kategori_key UNIQUE (nama_kategori);


--
-- Name: kategori_bop kategori_bop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_bop
    ADD CONSTRAINT kategori_bop_pkey PRIMARY KEY (id);


--
-- Name: kategori_kas kategori_kas_nama_kategori_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_kas
    ADD CONSTRAINT kategori_kas_nama_kategori_key UNIQUE (nama_kategori);


--
-- Name: kategori_kas kategori_kas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kategori_kas
    ADD CONSTRAINT kategori_kas_pkey PRIMARY KEY (id);


--
-- Name: keluarga keluarga_no_kk_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keluarga
    ADD CONSTRAINT keluarga_no_kk_key UNIQUE (no_kk);


--
-- Name: keluarga keluarga_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keluarga
    ADD CONSTRAINT keluarga_pkey PRIMARY KEY (id);


--
-- Name: letters letters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.letters
    ADD CONSTRAINT letters_pkey PRIMARY KEY (id);


--
-- Name: menu_items menu_items_kode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_kode_key UNIQUE (kode);


--
-- Name: menu_items menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);


--
-- Name: payment_transaction_bills payment_transaction_bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transaction_bills
    ADD CONSTRAINT payment_transaction_bills_pkey PRIMARY KEY (transaction_id, bill_id);


--
-- Name: payment_transactions payment_transactions_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_order_id_key UNIQUE (order_id);


--
-- Name: payment_transactions payment_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_pkey PRIMARY KEY (id);


--
-- Name: pembacaan_meteran pembacaan_meteran_kk_periode_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_kk_periode_uniq UNIQUE (keluarga_id, periode);


--
-- Name: pembacaan_meteran pembacaan_meteran_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_pkey PRIMARY KEY (id);


--
-- Name: polling_options polling_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_options
    ADD CONSTRAINT polling_options_pkey PRIMARY KEY (id);


--
-- Name: polling polling_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling
    ADD CONSTRAINT polling_pkey PRIMARY KEY (id);


--
-- Name: polling_votes polling_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes
    ADD CONSTRAINT polling_votes_pkey PRIMARY KEY (id);


--
-- Name: polling_votes polling_votes_polling_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes
    ADD CONSTRAINT polling_votes_polling_id_user_id_key UNIQUE (polling_id, user_id);


--
-- Name: reset_logs reset_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reset_logs
    ADD CONSTRAINT reset_logs_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_role_menu_kode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_menu_kode_key UNIQUE (role, menu_kode);


--
-- Name: sensor_logs sensor_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_logs
    ADD CONSTRAINT sensor_logs_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_nik_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_nik_key UNIQUE (nik);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: visitors visitors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitors
    ADD CONSTRAINT visitors_pkey PRIMARY KEY (id);


--
-- Name: bill_payments_satu_per_tagihan; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX bill_payments_satu_per_tagihan ON public.bill_payments USING btree (bill_id);


--
-- Name: bills_bulan_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bills_bulan_status_idx ON public.bills USING btree (bulan, status);


--
-- Name: bills_kk_jenis_bulan_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX bills_kk_jenis_bulan_uniq ON public.bills USING btree (keluarga_id, jenis_iuran_id, bulan) WHERE (keluarga_id IS NOT NULL);


--
-- Name: bop_finances_tanggal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bop_finances_tanggal_idx ON public.bop_finances USING btree (tanggal DESC);


--
-- Name: borrowings_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX borrowings_status_idx ON public.borrowings USING btree (status, inventory_id);


--
-- Name: finances_ref_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX finances_ref_uniq ON public.finances USING btree (ref_id) WHERE (ref_id IS NOT NULL);


--
-- Name: finances_tanggal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finances_tanggal_idx ON public.finances USING btree (tanggal DESC);


--
-- Name: idx_activity_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_logs_created_at ON public.activity_logs USING btree (created_at DESC);


--
-- Name: idx_activity_logs_tipe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_logs_tipe ON public.activity_logs USING btree (tipe);


--
-- Name: idx_activity_logs_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_logs_user ON public.activity_logs USING btree (user_id, created_at DESC);


--
-- Name: idx_agenda_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agenda_aktif ON public.agenda USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_anggota_keluarga_kk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anggota_keluarga_kk ON public.anggota_keluarga USING btree (keluarga_id);


--
-- Name: idx_bantuan_sosial_jenis; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bantuan_sosial_jenis ON public.bantuan_sosial USING btree (jenis_bantuan);


--
-- Name: idx_bantuan_sosial_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bantuan_sosial_status ON public.bantuan_sosial USING btree (status);


--
-- Name: idx_bantuan_sosial_tahun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bantuan_sosial_tahun ON public.bantuan_sosial USING btree (tahun);


--
-- Name: idx_bantuan_sosial_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bantuan_sosial_user_id ON public.bantuan_sosial USING btree (user_id);


--
-- Name: idx_bill_payments_bill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_payments_bill ON public.bill_payments USING btree (bill_id);


--
-- Name: idx_borrowings_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_borrowings_user ON public.borrowings USING btree (user_id);


--
-- Name: idx_complaints_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_complaints_aktif ON public.complaints USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_complaints_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_complaints_status ON public.complaints USING btree (status);


--
-- Name: idx_complaints_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_complaints_user ON public.complaints USING btree (user_id);


--
-- Name: idx_finances_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_finances_aktif ON public.finances USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_inventory_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_aktif ON public.inventory USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_keluarga_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_keluarga_aktif ON public.keluarga USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_letters_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_letters_aktif ON public.letters USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_letters_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_letters_status ON public.letters USING btree (status);


--
-- Name: idx_letters_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_letters_user ON public.letters USING btree (user_id);


--
-- Name: idx_payment_trx_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_trx_user ON public.payment_transactions USING btree (user_id);


--
-- Name: idx_polling_options_polling; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_polling_options_polling ON public.polling_options USING btree (polling_id);


--
-- Name: idx_users_aktif; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_aktif ON public.users USING btree (id) WHERE (deleted_at IS NULL);


--
-- Name: idx_users_nik; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_nik ON public.users USING btree (nik);


--
-- Name: idx_visitors_pembuat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_visitors_pembuat ON public.visitors USING btree (created_by);


--
-- Name: idx_visitors_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_visitors_status ON public.visitors USING btree (status);


--
-- Name: idx_visitors_tanggal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_visitors_tanggal ON public.visitors USING btree (((jam_masuk)::date));


--
-- Name: idx_visitors_tipe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_visitors_tipe ON public.visitors USING btree (tipe_keperluan);


--
-- Name: payment_bill_pending_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payment_bill_pending_uniq ON public.payment_transaction_bills USING btree (bill_id) WHERE is_pending;


--
-- Name: payment_transactions_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_transactions_status_idx ON public.payment_transactions USING btree (status, created_at DESC);


--
-- Name: pembacaan_meteran_periode_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pembacaan_meteran_periode_idx ON public.pembacaan_meteran USING btree (periode, status);


--
-- Name: reset_logs_waktu; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reset_logs_waktu ON public.reset_logs USING btree (created_at DESC);


--
-- Name: role_permissions_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX role_permissions_lookup ON public.role_permissions USING btree (role, menu_kode);


--
-- Name: activity_logs trg_activity_logs_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_logs_append_only BEFORE DELETE OR UPDATE ON public.activity_logs FOR EACH ROW EXECUTE FUNCTION public.tolak_ubah_activity_logs();


--
-- Name: activity_logs trg_activity_logs_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_logs_no_truncate BEFORE TRUNCATE ON public.activity_logs FOR EACH STATEMENT EXECUTE FUNCTION public.tolak_ubah_activity_logs();


--
-- Name: agenda agenda_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda
    ADD CONSTRAINT agenda_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: alokasi_bop alokasi_bop_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alokasi_bop
    ADD CONSTRAINT alokasi_bop_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: anggota_keluarga anggota_keluarga_keluarga_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anggota_keluarga
    ADD CONSTRAINT anggota_keluarga_keluarga_id_fkey FOREIGN KEY (keluarga_id) REFERENCES public.keluarga(id) ON DELETE CASCADE;


--
-- Name: announcements announcements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: bantuan_sosial bantuan_sosial_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial
    ADD CONSTRAINT bantuan_sosial_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: bantuan_sosial_log bantuan_sosial_log_bantuan_sosial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial_log
    ADD CONSTRAINT bantuan_sosial_log_bantuan_sosial_id_fkey FOREIGN KEY (bantuan_sosial_id) REFERENCES public.bantuan_sosial(id) ON DELETE CASCADE;


--
-- Name: bantuan_sosial_log bantuan_sosial_log_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial_log
    ADD CONSTRAINT bantuan_sosial_log_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: bantuan_sosial bantuan_sosial_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bantuan_sosial
    ADD CONSTRAINT bantuan_sosial_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bill_payments bill_payments_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT bill_payments_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id);


--
-- Name: bill_payments bill_payments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT bill_payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: bills bills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: bills bills_jenis_iuran_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_jenis_iuran_id_fkey FOREIGN KEY (jenis_iuran_id) REFERENCES public.jenis_iuran(id);


--
-- Name: bills bills_keluarga_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_keluarga_id_fkey FOREIGN KEY (keluarga_id) REFERENCES public.keluarga(id) ON DELETE CASCADE;


--
-- Name: bills bills_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: bop_finances bop_finances_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bop_finances
    ADD CONSTRAINT bop_finances_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: bop_finances bop_finances_kategori_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bop_finances
    ADD CONSTRAINT bop_finances_kategori_id_fkey FOREIGN KEY (kategori_id) REFERENCES public.kategori_bop(id);


--
-- Name: borrowings borrowings_dicatat_oleh_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.borrowings
    ADD CONSTRAINT borrowings_dicatat_oleh_fkey FOREIGN KEY (dicatat_oleh) REFERENCES public.users(id);


--
-- Name: borrowings borrowings_inventory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.borrowings
    ADD CONSTRAINT borrowings_inventory_id_fkey FOREIGN KEY (inventory_id) REFERENCES public.inventory(id) ON DELETE CASCADE;


--
-- Name: borrowings borrowings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.borrowings
    ADD CONSTRAINT borrowings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: complaints complaints_responded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_responded_by_fkey FOREIGN KEY (responded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: complaints complaints_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: emergency_alerts emergency_alerts_dismissed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_alerts
    ADD CONSTRAINT emergency_alerts_dismissed_by_fkey FOREIGN KEY (dismissed_by) REFERENCES public.users(id);


--
-- Name: emergency_alerts emergency_alerts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_alerts
    ADD CONSTRAINT emergency_alerts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: finances finances_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finances
    ADD CONSTRAINT finances_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: finances finances_kategori_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finances
    ADD CONSTRAINT finances_kategori_id_fkey FOREIGN KEY (kategori_id) REFERENCES public.kategori_kas(id);


--
-- Name: inventory inventory_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: letters letters_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.letters
    ADD CONSTRAINT letters_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- Name: letters letters_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.letters
    ADD CONSTRAINT letters_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: payment_transaction_bills payment_transaction_bills_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transaction_bills
    ADD CONSTRAINT payment_transaction_bills_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id) ON DELETE CASCADE;


--
-- Name: payment_transaction_bills payment_transaction_bills_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transaction_bills
    ADD CONSTRAINT payment_transaction_bills_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES public.payment_transactions(id) ON DELETE CASCADE;


--
-- Name: payment_transactions payment_transactions_keluarga_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_keluarga_id_fkey FOREIGN KEY (keluarga_id) REFERENCES public.keluarga(id) ON DELETE CASCADE;


--
-- Name: payment_transactions payment_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: pembacaan_meteran pembacaan_meteran_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id) ON DELETE SET NULL;


--
-- Name: pembacaan_meteran pembacaan_meteran_diisi_oleh_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_diisi_oleh_fkey FOREIGN KEY (diisi_oleh) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: pembacaan_meteran pembacaan_meteran_dikoreksi_oleh_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_dikoreksi_oleh_fkey FOREIGN KEY (dikoreksi_oleh) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: pembacaan_meteran pembacaan_meteran_keluarga_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pembacaan_meteran
    ADD CONSTRAINT pembacaan_meteran_keluarga_id_fkey FOREIGN KEY (keluarga_id) REFERENCES public.keluarga(id) ON DELETE CASCADE;


--
-- Name: polling polling_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling
    ADD CONSTRAINT polling_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: polling_options polling_options_polling_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_options
    ADD CONSTRAINT polling_options_polling_id_fkey FOREIGN KEY (polling_id) REFERENCES public.polling(id) ON DELETE CASCADE;


--
-- Name: polling_votes polling_votes_option_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes
    ADD CONSTRAINT polling_votes_option_id_fkey FOREIGN KEY (option_id) REFERENCES public.polling_options(id) ON DELETE CASCADE;


--
-- Name: polling_votes polling_votes_polling_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes
    ADD CONSTRAINT polling_votes_polling_id_fkey FOREIGN KEY (polling_id) REFERENCES public.polling(id) ON DELETE CASCADE;


--
-- Name: polling_votes polling_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polling_votes
    ADD CONSTRAINT polling_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reset_logs reset_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reset_logs
    ADD CONSTRAINT reset_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: role_permissions role_permissions_menu_kode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_menu_kode_fkey FOREIGN KEY (menu_kode) REFERENCES public.menu_items(kode) ON DELETE CASCADE;


--
-- Name: visitors visitors_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitors
    ADD CONSTRAINT visitors_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--


