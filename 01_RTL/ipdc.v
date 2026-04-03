
module ipdc (  //Don't modify interface
    input         i_clk,
    input         i_rst_n,
    input         i_op_valid,
    input  [ 3:0] i_op_mode,
    output        o_op_ready,
    input         i_in_valid,
    input  [23:0] i_in_data,
    output        o_in_ready,
    output        o_out_valid,
    output [23:0] o_out_data
);

  // ---------------------------------------------------------------------------
  // Wires and Registers
  // ---------------------------------------------------------------------------
  // ---- Add your own wires and registers here if needed ---- //
  reg o_in_ready_w, o_in_ready_r;
  reg o_op_ready_w, o_op_ready_r;
  reg o_out_data_w, o_out_data_r;
  reg [23:0] Image[0:15][0:15];  // 16x16 image
  reg [23:0] scaled_8x8[0:7][0:7];
  reg [23:0] scaled_4x4[0:3][0:3];
  reg [23:0] p00, p01, p02;
  reg [23:0] p10, p11, p12;
  reg [23:0] p20, p21, p22;
  reg [23:0] fil_pixel;
  reg [7:0] r_med, g_med, b_med;
  reg [3:0] row_pos, prev_row_pos, org_row_pos, prev_org_row_pos;
  reg [3:0] col_pos, prev_col_pos, org_col_pos, prev_org_col_pos;
  reg [3:0] shifted_org_row, shifted_org_col;
  reg [3:0] eff_org_row_pos, eff_org_col_pos;
  reg [3:0] up_org_row, up_org_col;
  reg [3:0] fil_pix_row, fil_pix_col;
  reg [3:0] src_row, src_col;
  reg [2:0] pixel_col_count, prev_pixel_col_count;
  reg [2:0] pixel_row_count, prev_pixel_row_count;
  reg [1:0] image_size;  //00 = 16x16, 01 = 8x8, 11 = 4x4
  reg [7:0] R, G, B;
  reg [10:0] Y_num;
  reg signed [11:0] Cb_num, Cr_num;
  reg [7:0] Y_out, Cb_out, Cr_out;
  integer r, c;
  integer disp_max;
  integer ii, jj;

  // ---------------------------------------------------------------------------
  // Continuous Assignment
  // ---------------------------------------------------------------------------
  // ---- Add your own wire data assignments here if needed ---- //
  assign o_op_ready  = o_op_ready_r;
  assign o_in_ready  = o_in_ready_r;
  assign o_out_data  = o_out_data_r;
  assign o_out_valid = o_out_valid_r;

  function [23:0] get_cur_pixel;
    input integer rr;
    input integer cc;
    begin

      case (image_size)
        2'b00: begin
          get_cur_pixel=  ((rr >= 0) && (rr < 16) && (cc >= 0) && (cc < 16)) ? Image[rr][cc] : 24'd0;
        end

        2'b01: begin
          get_cur_pixel = ((rr >= 0) && (rr < 8) && (cc >= 0) && (cc < 8)) ? scaled_8x8[rr][cc] : 24'd0;
        end

        2'b11: begin
          get_cur_pixel = ((rr >= 0) && (rr < 4) && (cc >= 0) && (cc < 4)) ? scaled_4x4[rr][cc] : 24'd0;
        end

        default: begin
          get_cur_pixel = 24'd0;
        end
      endcase
    end
  endfunction

  function [7:0] median9;
    input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
    reg [7:0] a[0:8];
    reg [7:0] tmp;
    integer i, j;
    begin
      a[0] = v0;
      a[1] = v1;
      a[2] = v2;
      a[3] = v3;
      a[4] = v4;
      a[5] = v5;
      a[6] = v6;
      a[7] = v7;
      a[8] = v8;

      for (i = 0; i < 8; i = i + 1) begin
        for (j = 0; j < 8 - i; j = j + 1) begin
          if (a[j] > a[j+1]) begin
            tmp    = a[j];
            a[j]   = a[j+1];
            a[j+1] = tmp;
          end
        end
      end

      median9 = a[4];
    end
  endfunction

  function [7:0] Census;
    input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
    begin
      Census = {
        (v0 > v4), (v1 > v4), (v2 > v4), (v3 > v4), (v5 > v4), (v6 > v4), (v7 > v4), (v8 > v4)
      };
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Combinational Blocks
  // ---------------------------------------------------------------------------
  // ---- Write your conbinational block design here ---- //
  // effective origin for current image size
  always @(*) begin
    case (image_size)
      2'b00: begin  // 16x16
        eff_org_row_pos = prev_org_row_pos;
        eff_org_col_pos = prev_org_col_pos;
      end
      2'b01: begin  // 8x8
        eff_org_row_pos = prev_org_row_pos >> 1;
        eff_org_col_pos = prev_org_col_pos >> 1;
      end
      2'b11: begin  // 4x4
        eff_org_row_pos = prev_org_row_pos >> 2;
        eff_org_col_pos = prev_org_col_pos >> 2;
      end
      default: begin
        eff_org_row_pos = 4'd0;
        eff_org_col_pos = 4'd0;
      end
    endcase
  end

  always @(*) begin
    o_in_ready_w = 1'b0;
    o_op_ready_w = 1'b0;
    o_out_data_w = 24'd0;
    o_out_valid_w = 1'b0;
    row_pos = prev_row_pos;
    col_pos = prev_col_pos;
    org_row_pos = prev_org_row_pos;
    org_col_pos = prev_org_col_pos;
    pixel_row_count = prev_pixel_row_count;
    pixel_col_count = prev_pixel_col_count;

    if (i_op_valid) begin
      case (i_op_mode)
        4'b0000: begin
          if (i_in_valid) begin
            Image[row_pos][col_pos] = in_data;
            o_in_ready_w = 1'b1;
            if (col_pos < 4'd15) begin
              col_pos = prev_col_pos + 4'd1;
            end else begin
              col_pos = 5'd0;
              if (row_pos < 4'd15) begin
                row_pos = prev_row_pos + 4'd1;
              end else begin
                row_pos = 4'd0;
                o_op_ready_w = 1'b1;
                org_col_pos = 4'd0;
                org_row_pos = 4'd0;
                image_size = 2'd00;
              end
            end
          end
        end  //Load Image

        4'b0100: begin
          if (image_size == 2'b00) begin
            shifted_org_row = prev_org_row_pos;
            shifted_org_col = (prev_org_col_pos < 4'd12) ? prev_org_col_pos + 4'd1 : 4'd12;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = Image[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd3) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col;
                org_row_pos = shifted_org_row;
                image_size = 2'b00;
              end
            end
          end else if (image_size == 2'b01) begin
            shifted_org_row = eff_org_row_pos;
            shifted_org_col = (eff_org_col_pos < 4'd6) ? (eff_org_col_pos + 4'd1) : 4'd6;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_8x8[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w = 1'b1;
                org_col_pos = shifted_org_col >> 1;
                org_row_pos = shifted_org_row >> 1;
                image_size = 2'b01;
              end
            end
          end else if (image_size == 2'b11) begin
            shifted_org_row = eff_org_row_pos;
            shifted_org_col = (eff_org_col_pos < 4'd3) ? eff_org_col_pos + 4'd1 : 4'd3;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_4x4[src_row][src_col];
            o_out_valid_w = 1'b1;
            o_op_ready_w = 1'b1;
            image_size = 2'b11;
            org_col_pos = shifted_org_col >> 2;
            org_row_pos = shifted_org_row >> 2;
          end
        end  //Shift Origin Right

        4'b0101: begin
          if (image_size == 2'b00) begin
            shifted_org_row = prev_org_row_pos;
            shifted_org_col = (prev_org_col_pos > 4'd0) ? prev_org_col_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = Image[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd3) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col;
                org_row_pos = shifted_org_row;
                image_size = 2'b00;
              end
            end
          end else if (image_size == 2'b01) begin
            shifted_org_row = eff_org_row_pos;
            shifted_org_col = (eff_org_col_pos > 4'd0) ? eff_org_col_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_8x8[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col >> 1;
                org_row_pos = shifted_org_row >> 1;
                image_size = 2'b01;
              end
            end
          end else if (image_size == 2'b11) begin
            shifted_org_row = eff_org_row_pos;
            shifted_org_col = (eff_org_col_pos > 4'd0) ? eff_org_col_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_4x4[src_row][src_col];

            o_out_valid_w = 1'b1;
            o_op_ready_w = 1'b1;
            image_size = 2'b11;
            org_col_pos = shifted_org_col >> 2;
            org_row_pos = shifted_org_row >> 2;
          end
        end  // Shift Origin Left

        4'b0110: begin
          if (image_size == 2'b00) begin
            shifted_org_col = prev_org_col_pos;
            shifted_org_row = (prev_org_row_pos > 4'd0) ? prev_org_row_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;
            o_out_data_w = Image[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd3) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col;
                org_row_pos = shifted_org_row;
                image_size = 2'b00;
              end
            end
          end else if (image_size == 2'b01) begin
            shifted_org_col = eff_org_col_pos;
            shifted_org_row = (eff_org_row_pos > 4'd0) ? eff_org_row_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_8x8[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col >> 1;
                org_row_pos = shifted_org_row >> 1;
                image_size = 2'b01;
              end
            end
          end else if (image_size == 2'b11) begin
            shifted_org_col = eff_org_col_pos;
            shifted_org_row = (eff_org_row_pos > 4'd0) ? eff_org_row_pos - 4'd1 : 4'd0;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;
            o_out_data_w = scaled_4x4[src_row][src_col];
            o_out_valid_w = 1'b1;

            o_op_ready_w = 1'b1;
            org_col_pos = shifted_org_col >> 2;
            org_row_pos = shifted_org_row >> 2;
            image_size = 2'b11;
          end
        end  // Shift Origin Up

        4'b0111: begin
          if (image_size == 2'b00) begin
            shifted_org_col = prev_org_col_pos;
            shifted_org_row = (prev_org_row_pos < 4'd12) ? prev_org_row_pos + 4'd1 : 4'd12;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = Image[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd3) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col;
                org_row_pos = shifted_org_row;
                image_size = 2'b00;
              end
            end
          end else if (image_size == 2'b01) begin
            shifted_org_col = eff_org_col_pos;
            shifted_org_row = (eff_org_row_pos < 4'd6) ? eff_org_row_pos + 4'd1 : 4'd6;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_8x8[src_row][src_col];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 1;
              end else begin
                o_op_ready_w = 1'b1;
                pixel_row_count = 3'd0;
                org_col_pos = shifted_org_col >> 1;
                org_row_pos = shifted_org_row >> 1;
                image_size = 2'b01;
              end
            end
          end else if (image_size == 2'b11) begin
            shifted_org_col = eff_org_col_pos;
            shifted_org_row = (eff_org_row_pos < 4'd3) ? eff_org_row_pos + 4'd1 : 4'd3;

            src_row = shifted_org_row + prev_pixel_row_count;
            src_col = shifted_org_col + prev_pixel_col_count;

            o_out_data_w = scaled_4x4[src_row][src_col];
            o_out_valid_w = 1'b1;
            o_op_ready_w = 1'b1;
            image_size = 2'b11;
            org_col_pos = shifted_org_col >> 2;
            org_row_pos = shifted_org_row >> 2;
          end
        end  // Shift Origin Down

        4'b1000: begin
          if (image_size == 2'b00) begin  // 16x16 -> 8x8, display 2x2
            down_org_row = eff_org_row_pos >> 1;
            down_org_col = eff_org_col_pos >> 1;

            for (r = 0; r < 8; r = r + 1) begin
              for (c = 0; c < 8; c = c + 1) begin
                scaled_8x8[r][c] = Image[(r<<1)+prev_org_row_pos[0]][(c<<1)+prev_org_col_pos[0]];
              end
            end
            o_out_data_w  = scaled_8x8[down_org_row + prev_pixel_row_count][down_org_col + prev_pixel_col_count];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 3'd1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w    = 1'b1;
                image_size      = 2'b01;
              end
            end
          end else if (image_size == 2'b01) begin  // 8x8 -> 4x4, display 1x1
            down_org_row = eff_org_row_pos >> 1;
            down_org_col = eff_org_col_pos >> 1;

            for (r = 0; r < 4; r = r + 1) begin
              for (c = 0; c < 4; c = c + 1) begin
                scaled_4x4[r][c] = scaled_8x8[(r<<1)+eff_org_row_pos[0]][(c<<1)+eff_org_col_pos[0]];
              end
            end
            o_out_data_w = scaled_4x4[down_org_row][down_org_col];  //fix origin
            o_out_valid_w = 1'b1;
            o_op_ready_w = 1'b1;
            image_size = 2'b11;
          end
        end  // Scale Down

        4'b1001: begin
          if (image_size == 2'b11) begin  // 4x4 -> 8x8, display 2x2
            up_org_row = (up_org_row > 4'd6) ? 4'd6 : eff_org_row_pos << 1;
            up_org_col = (up_org_col > 4'd6) ? 4'd6 : eff_org_col_pos << 1;

            o_out_data_w  = scaled_8x8[up_org_row + prev_pixel_row_count][up_org_col + prev_pixel_col_count];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
              pixel_row_count = prev_pixel_row_count;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd1) begin
                pixel_row_count = prev_pixel_row_count + 3'd1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w    = 1'b1;
                image_size      = 2'b01;
              end
            end
          end else if (image_size == 2'b01) begin  // 8x8 -> 16x16, display 4x4
            up_org_row = (up_org_row > 4'd12) ? 4'd12 : eff_org_row_pos << 1;
            up_org_col = (up_org_col > 4'd12) ? 4'd12 : eff_org_col_pos << 1;

            o_out_data_w = Image[up_org_row+prev_pixel_row_count][up_org_col+prev_pixel_col_count];
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3'd3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
              pixel_row_count = prev_pixel_row_count;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3'd3) begin
                pixel_row_count = prev_pixel_row_count + 3'd1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w    = 1'b1;
                image_size      = 2'b00;
              end
            end
          end
        end  // Scale Up
        4'b1100: begin

          if (image_size == 2'b00) disp_max = 3;  // 4x4 output
          else if (image_size == 2'b01) disp_max = 1;  // 2x2 output
          else disp_max = 0;  // 1x1 output

          center_row = eff_org_row_pos + prev_pixel_row_count;
          center_col = eff_org_col_pos + prev_pixel_col_count;

          p00 = get_cur_pixel(center_row - 1, center_col - 1);
          p01 = get_cur_pixel(center_row - 1, center_col);
          p02 = get_cur_pixel(center_row - 1, center_col + 1);

          p10 = get_cur_pixel(center_row, center_col - 1);
          p11 = get_cur_pixel(center_row, center_col);
          p12 = get_cur_pixel(center_row, center_col + 1);

          p20 = get_cur_pixel(center_row + 1, center_col - 1);
          p21 = get_cur_pixel(center_row + 1, center_col);
          p22 = get_cur_pixel(center_row + 1, center_col + 1);

          r_med = median9(
            p00[23:16],
            p01[23:16],
            p02[23:16],
            p10[23:16],
            p11[23:16],
            p12[23:16],
            p20[23:16],
            p21[23:16],
            p22[23:16]
          );

          g_med = median9(
            p00[15:8],
            p01[15:8],
            p02[15:8],
            p10[15:8],
            p11[15:8],
            p12[15:8],
            p20[15:8],
            p21[15:8],
            p22[15:8]
          );

          b_med = median9(p00[7:0], p01[7:0], p02[7:0], p10[7:0], p11[7:0], p12[7:0], p20[7:0],
                          p21[7:0], p22[7:0]);

          o_out_data_w = {r_med, g_med, b_med};
          o_out_valid_w = 1'b1;

          if (prev_pixel_col_count < disp_max) begin
            pixel_col_count = prev_pixel_col_count + 3'd1;
            pixel_row_count = prev_pixel_row_count;
          end else begin
            pixel_col_count = 3'd0;
            if (prev_pixel_row_count < disp_max) begin
              pixel_row_count = prev_pixel_row_count + 3'd1;
            end else begin
              pixel_row_count = 3'd0;
              o_op_ready_w    = 1'b1;
            end
          end
        end  // Median Filter

        4'b1101: begin
          if (image_size == 2'b00) begin
            fil_pix_row = eff_org_row_pos + prev_pixel_row_count;
            fil_pix_col = eff_org_col_pos + prev_pixel_col_count;
            fil_pixel = Image[fil_pix_row][fil_pix_col];

            Rn = fil_pixel[23:16];
            Gn = fil_pixel[15:8];
            Bn = fil_pixel[7:0];

            // Y  = (2R + 5G)/8, Cb = (-R - 2G + 4B)/8 + 128, Cr = (4R - 3G - B)/8 + 128
            Y_num = (Rn << 1) + (Gn << 2) + Gn;
            Cb_num = -$signed({1'b0, Rn}) - ($signed({1'b0, Gn}) << 1) + ($signed({1'b0, Bn}) << 2);
            Cr_num = ($signed({1'b0, Rn}) << 2) -
                (($signed({1'b0, Gn}) << 1) + $signed({1'b0, Gn})) - $signed({1'b0, Bn});

            Y_out = (Y_num + 4) >>> 3;
            Cb_out = ((Cb_num + 4) >>> 3) + 8'd128;
            Cr_out = ((Cr_num + 4) >>> 3) + 8'd128;

            o_out_data_w = {Y_out, Cb_out, Cr_out};
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 3) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
              pixel_row_count = prev_pixel_row_count;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 3) begin
                pixel_row_count = prev_pixel_row_count + 3'd1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w    = 1'b1;
              end
            end
          end else if (image_size == 2'b01) begin
            fil_pix_row = eff_org_row_pos + prev_pixel_row_count;
            fil_pix_col = eff_org_col_pos + prev_pixel_col_count;
            fil_pixel = scaled_8x8[fil_pix_row][fil_pix_col];

            Rn = fil_pixel[23:16];
            Gn = fil_pixel[15:8];
            Bn = fil_pixel[7:0];

            // Y  = (2R + 5G)/8, Cb = (-R - 2G + 4B)/8 + 128, Cr = (4R - 3G - B)/8 + 128
            Y_num = (Rn << 1) + (Gn << 2) + Gn;
            Cb_num = -$signed({1'b0, Rn}) - ($signed({1'b0, Gn}) << 1) + ($signed({1'b0, Bn}) << 2);
            Cr_num = ($signed({1'b0, Rn}) << 2) -
                (($signed({1'b0, Gn}) << 1) + $signed({1'b0, Gn})) - $signed({1'b0, Bn});

            Y_out = (Y_num + 4) >>> 3;
            Cb_out = ((Cb_num + 4) >>> 3) + 8'd128;
            Cr_out = ((Cr_num + 4) >>> 3) + 8'd128;

            o_out_data_w = {Y_out, Cb_out, Cr_out};
            o_out_valid_w = 1'b1;

            if (prev_pixel_col_count < 1) begin
              pixel_col_count = prev_pixel_col_count + 3'd1;
              pixel_row_count = prev_pixel_row_count;
            end else begin
              pixel_col_count = 3'd0;
              if (prev_pixel_row_count < 1) begin
                pixel_row_count = prev_pixel_row_count + 3'd1;
              end else begin
                pixel_row_count = 3'd0;
                o_op_ready_w    = 1'b1;
              end
            end
          end else begin
            fil_pix_row = eff_org_row_pos + prev_pixel_row_count;
            fil_pix_col = eff_org_col_pos + prev_pixel_col_count;
            fil_pixel = scaled_4x4[fil_pix_row][fil_pix_col];

            R = fil_pixel[23:16];
            G = fil_pixel[15:8];
            B = fil_pixel[7:0];

            // Y  = (2R + 5G)/8, Cb = (-R - 2G + 4B)/8 + 128, Cr = (4R - 3G - B)/8 + 128
            Y_num = (R << 1) + (G << 2) + G;
            Cb_num = -$signed({1'b0, R}) - ($signed({1'b0, G}) << 1) + ($signed({1'b0, B}) << 2);
            Cr_num = ($signed({1'b0, R}) << 2) - (($signed({1'b0, G}) << 1) + $signed({1'b0, G})) -
                $signed({1'b0, B});
            Y_out = (Y_num + 4) >>> 3;
            Cb_out = ((Cb_num + 4) >>> 3) + 8'd128;
            Cr_out = ((Cr_num + 4) >>> 3) + 8'd128;

            o_out_data_w = {Y_out, Cb_out, Cr_out};
            o_out_valid_w = 1'b1;
            o_op_ready_w = 1'b1;
          end  // 1x1 output
        end  //YCbCr
        4'b1110: begin
          if (image_size == 2'b00) disp_max = 3;  // 4x4 output
          else if (image_size == 2'b01) disp_max = 1;  // 2x2 output
          else disp_max = 0;  // 1x1 output

          center_row = eff_org_row_pos + prev_pixel_row_count;
          center_col = eff_org_col_pos + prev_pixel_col_count;

          p00 = get_cur_pixel(center_row - 1, center_col - 1);
          p01 = get_cur_pixel(center_row - 1, center_col);
          p02 = get_cur_pixel(center_row - 1, center_col + 1);

          p10 = get_cur_pixel(center_row, center_col - 1);
          p11 = get_cur_pixel(center_row, center_col);
          p12 = get_cur_pixel(center_row, center_col + 1);

          p20 = get_cur_pixel(center_row + 1, center_col - 1);
          p21 = get_cur_pixel(center_row + 1, center_col);
          p22 = get_cur_pixel(center_row + 1, center_col + 1);

          r_cen = Census(
            p00[23:16],
            p01[23:16],
            p02[23:16],
            p10[23:16],
            p11[23:16],
            p12[23:16],
            p20[23:16],
            p21[23:16],
            p22[23:16]
          );

          g_cen = Census(
            p00[15:8],
            p01[15:8],
            p02[15:8],
            p10[15:8],
            p11[15:8],
            p12[15:8],
            p20[15:8],
            p21[15:8],
            p22[15:8]
          );

          b_cen = Census(p00[7:0], p01[7:0], p02[7:0], p10[7:0], p11[7:0], p12[7:0], p20[7:0],
                         p21[7:0], p22[7:0]);

          o_out_data_w = {r_cen, g_cen, b_cen};
          o_out_valid_w = 1'b1;

          if (prev_pixel_col_count < disp_max) begin
            pixel_col_count = prev_pixel_col_count + 3'd1;
            pixel_row_count = prev_pixel_row_count;
          end else begin
            pixel_col_count = 3'd0;
            if (prev_pixel_row_count < disp_max) begin
              pixel_row_count = prev_pixel_row_count + 3'd1;
            end else begin
              pixel_row_count = 3'd0;
              o_op_ready_w    = 1'b1;
            end
          end
        end  //Census

        default: begin
          o_op_ready_w = 1'b0;
          o_out_valid  = 1'b0;
          o_out_data_w = 24'b0;
          o_in_ready_w = 24'b0;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential Block
  // ---------------------------------------------------------------------------
  // ---- Write your sequential block design here ---- //

  always @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin
      prev_row_pos <= 4'd00;
      prev_col_pos <= 4'd0;
      prev_org_row <= 4'd0;
      prev_org_col <= 4'd0;
      prev_pixel_col_count <= 3'd0;
      prev_pixel_row_count <= 3'd0;
      o_in_ready_r <= 0;
      o_op_ready_r <= 0;
      o_out_data_r <= 24'd0;
      o_out_valid_r <= 1'b0;
    end else begin
      o_in_ready_r <= o_in_ready_w;
      o_op_ready_r <= o_op_ready_w;
      o_out_valid_r <= o_out_valid_w;
      o_out_data_r <= o_out_data_w;
      prev_pixel_col_count <= pixel_col_count;
      prev_pixel_row_count <= pixel_row_count;
      prev_row_pos <= row_pos;
      prev_col_pos <= col_pos;
      prev_org_row_pos <= org_row_pos;
      prev_org_col_pos <= org_prev_col_pos;
    end
  end
endmodule
