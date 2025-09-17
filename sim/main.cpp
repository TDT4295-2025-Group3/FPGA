#include <verilated.h>
#include <SDL2/SDL.h>
#include "Vtop_sim.h"

const int WIDTH = 640;
const int HEIGHT = 480;
const int OFFSET_X = 144;
const int OFFSET_Y = 34;

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vtop_sim *top = new Vtop_sim;
    top->btn_rst_n = 1;

    // --- SDL setup ---
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Window *window = SDL_CreateWindow("VGA Sim",
                                          SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                          WIDTH, HEIGHT,
                                          SDL_WINDOW_RESIZABLE);
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    // Use nearest-neighbor scaling to keep pixels sharp
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");

    SDL_Texture *texture = SDL_CreateTexture(renderer,
                                             SDL_PIXELFORMAT_RGB888,
                                             SDL_TEXTUREACCESS_STREAMING,
                                             WIDTH, HEIGHT);

    uint32_t *pixels = new uint32_t[WIDTH * HEIGHT];
    memset(pixels, 0, WIDTH * HEIGHT * sizeof(uint32_t)); // Initialize to black

    bool running = true;
    SDL_Event e;

    int x = -OFFSET_X;
    int y = -OFFSET_Y;
    bool prev_vsync = false;
    bool prev_hsync = false;
    bool prev_clk_pix = false;

    while (running)
    {
        bool frame_done = false;

        while (!frame_done)
        {
            // Toggle 100 MHz clock
            top->clk_100m = !top->clk_100m;
            top->eval();

            // Detect rising edge of pixel clock
            if (!prev_clk_pix && top->clk_pix)
            {
                // Edge detect VSYNC (frame start) - active low
                if (!prev_vsync && top->vga_vsync)
                {
                    x = -OFFSET_X;
                    y = -OFFSET_Y;
                    frame_done = true;
                }
                prev_vsync = top->vga_vsync;

                // Edge detect HSYNC (start of line) - active low
                if (prev_hsync && !top->vga_hsync)
                {
                    x = -OFFSET_X;
                    y++;
                }
                prev_hsync = top->vga_hsync;

                // Sample pixel data
                if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT)
                {
                    uint8_t r = (top->vga_r & 0xF) * 17;
                    uint8_t g = (top->vga_g & 0xF) * 17;
                    uint8_t b = (top->vga_b & 0xF) * 17;
                    pixels[y * WIDTH + x] = (r << 16) | (g << 8) | b;
                }
                x++;
            }
            prev_clk_pix = top->clk_pix;
        }

        // --- Rendering ---
        SDL_UpdateTexture(texture, NULL, pixels, WIDTH * sizeof(uint32_t));

        int win_w, win_h;
        SDL_GetWindowSize(window, &win_w, &win_h);

        float tex_aspect = (float)WIDTH / HEIGHT;
        float win_aspect = (float)win_w / win_h;

        SDL_Rect dest;
        if (win_aspect > tex_aspect)
        {
            // Window is wider than texture → pillarbox
            dest.h = win_h;
            dest.w = (int)(win_h * tex_aspect);
            dest.x = (win_w - dest.w) / 2;
            dest.y = 0;
        }
        else
        {
            // Window is taller than texture → letterbox
            dest.w = win_w;
            dest.h = (int)(win_w / tex_aspect);
            dest.x = 0;
            dest.y = (win_h - dest.h) / 2;
        }

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, texture, NULL, &dest);
        SDL_RenderPresent(renderer);

        while (SDL_PollEvent(&e))
        {
            if (e.type == SDL_QUIT)
                running = false;
        }
    }

    delete[] pixels;
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    delete top;
    return 0;
}
