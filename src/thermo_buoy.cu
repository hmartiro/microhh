/*
 * MicroHH
 * Copyright (c) 2011-2017 Chiel van Heerwaarden
 * Copyright (c) 2011-2017 Thijs Heus
 * Copyright (c) 2014-2017 Bart van Stratum
 *
 * This file is part of MicroHH
 *
 * MicroHH is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * MicroHH is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with MicroHH.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <cstdio>
#include "grid.h"
#include "fields.h"
#include "thermo_buoy.h"
#include "master.h"
#include "finite_difference.h"
#include "tools.h"

namespace
{
	__global__ 
    void calc_buoyancy_tend_2nd_g(double* __restrict__ wt, double* __restrict__ b, 
                                  int istart, int jstart, int kstart,
                                  int iend,   int jend,   int kend,
                                  int jj, int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart; 

        using Finite_difference::O2::interp2;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            wt[ijk] += interp2(b[ijk-kk], b[ijk]);
        }
    }
    
    __global__ 
    void calc_buoyancy_tend_u_2nd_g(double* const __restrict__ ut, const double* const __restrict__ b,
                                    const double sinalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend,   const int jend,   const int kend,
                                    const int jj,     const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int ii1 = 1;

        using Finite_difference::O2::interp2;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            ut[ijk] += sinalpha * interp2(b[ijk-ii1], b[ijk]);
        }
    }
    
    __global__ 
    void calc_buoyancy_tend_w_2nd_g(double* __restrict__ wt, const double* const __restrict__ b,
                                    const double cosalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend, const int jend, const int kend,
                                    const int jj, const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int kk1 = 1*kk;

        using Finite_difference::O2::interp2;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            wt[ijk] += cosalpha * interp2(b[ijk-kk1], b[ijk]);
        }
    }
    
    __global__ 
    void calc_buoyancy_tend_b_2nd_g(double* const __restrict__ bt,
                                    const double* const __restrict__ u, const double* const __restrict__ w,
                                    const double utrans, const double n2, const double sinalpha, const double cosalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend, const int jend, const int kend,
                                    const int jj, const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int ii1 = 1;
        const int kk1 = 1*kk;

        using Finite_difference::O2::interp2;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            bt[ijk] -= n2 * ( sinalpha * ( interp2(u[ijk], u[ijk+ii1]) + utrans )
                            + cosalpha * ( interp2(w[ijk], w[ijk+kk1]) ) );
        }
    }
    
    __global__ 
    void calc_buoyancy_tend_4th_g(double* __restrict__ wt, double* __restrict__ b, 
                                  int istart, int jstart, int kstart,
                                  int iend,   int jend,   int kend,
                                  int jj, int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int kk1 = 1*kk;
        const int kk2 = 2*kk;

        using namespace Finite_difference::O4;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            wt[ijk] += ci0*b[ijk-kk2] + ci1*b[ijk-kk1] + ci2*b[ijk] + ci3*b[ijk+kk1];
        }
    }
    
    __global__ 
    void calc_buoyancy_tend_u_4th_g(double* const __restrict__ ut, const double* const __restrict__ b,
                                    const double sinalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend,   const int jend,   const int kend,
                                    const int jj,     const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int ii1 = 1;
        const int ii2 = 2;

        using namespace Finite_difference::O4;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            ut[ijk] += sinalpha * (ci0*b[ijk-ii2] + ci1*b[ijk-ii1] + ci2*b[ijk] + ci3*b[ijk+ii1]);
        }
    }

    __global__ 
    void calc_buoyancy_tend_w_4th_g(double* __restrict__ wt, const double* const __restrict__ b,
                                    const double cosalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend, const int jend, const int kend,
                                    const int jj, const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int kk1 = 1*kk;
        const int kk2 = 2*kk;

        using namespace Finite_difference::O4;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            wt[ijk] += cosalpha * (ci0*b[ijk-kk2] + ci1*b[ijk-kk1] + ci2*b[ijk] + ci3*b[ijk+kk1]);
        }
    }

    __global__ 
    void calc_buoyancy_tend_b_4th_g(double* const __restrict__ bt,
                                    const double* const __restrict__ u, const double* const __restrict__ w,
                                    const double utrans, const double n2, const double sinalpha, const double cosalpha,
                                    const int istart, const int jstart, const int kstart,
                                    const int iend, const int jend, const int kend,
                                    const int jj, const int kk)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart; 
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart; 
        const int k = blockIdx.z + kstart;

        const int ii1 = 1;
        const int ii2 = 2;

        const int kk1 = 1*kk;
        const int kk2 = 2*kk;

        using namespace Finite_difference::O4;

        if (i < iend && j < jend && k < kend)
        {
            const int ijk = i + j*jj + k*kk;
            bt[ijk] -= n2 * ( sinalpha * ( (ci0*u[ijk-ii1] + ci1*u[ijk] + ci2*u[ijk+ii1] + ci3*u[ijk+ii2]) + utrans )
                            + cosalpha * (  ci0*w[ijk-kk1] + ci1*w[ijk] + ci2*w[ijk+kk1] + ci3*w[ijk+kk2]) );
        }
    }
} // End namespace.

#ifdef USECUDA
void Thermo_buoy::exec()
{
    const int blocki = grid->ithread_block;
    const int blockj = grid->jthread_block;
    const int gridi  = grid->imax/blocki + (grid->imax%blocki > 0);
    const int gridj  = grid->jmax/blockj + (grid->jmax%blockj > 0);

    dim3 gridGPU (gridi, gridj, grid->kmax-1);
    dim3 blockGPU(blocki, blockj, 1);

    const int offs = grid->memoffset;
    
    if (grid->swspatialorder== "2")
    {
        if (has_slope || has_N2)
        {
	        const double sinalpha = std::sin(this->alpha);
            const double cosalpha = std::cos(this->alpha);
		    
            calc_buoyancy_tend_u_2nd_g<<<gridGPU, blockGPU>>>(
                &fields->ut->data_g[offs], &fields->sp["b"]->data_g[offs],
                sinalpha,
                grid->istart,  grid->jstart, grid->kstart,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error(); 
		    
            calc_buoyancy_tend_w_2nd_g<<<gridGPU, blockGPU>>>(
                &fields->wt->data_g[offs], &fields->sp["b"]->data_g[offs],
                cosalpha,
                grid->istart,  grid->jstart, grid->kstart+1,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error(); 
		    
            calc_buoyancy_tend_b_2nd_g<<<gridGPU, blockGPU>>>(
                &fields->st["b"]->data_g[offs],
                &fields->u->data_g[offs], &fields->w->data_g[offs],
                grid->utrans, n2, sinalpha, cosalpha,
                grid->istart,  grid->jstart, grid->kstart,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error();
        }
        else 
        {
	        calc_buoyancy_tend_2nd_g<<<gridGPU, blockGPU>>>(
            &fields->wt->data_g[offs], &fields->sp["b"]->data_g[offs], 
            grid->istart,  grid->jstart, grid->kstart+1,
            grid->iend,    grid->jend,   grid->kend,
            grid->icellsp, grid->ijcellsp);
            cuda_check_error();
        }
    }
    else if (grid->swspatialorder== "4")
    {
        const double sinalpha = std::sin(this->alpha);
        const double cosalpha = std::cos(this->alpha);
        
        if (has_slope || has_N2)
        {
            calc_buoyancy_tend_u_4th_g<<<gridGPU, blockGPU>>>(
                &fields->ut->data_g[offs], &fields->sp["b"]->data_g[offs],
                sinalpha,
                grid->istart,  grid->jstart, grid->kstart,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error(); 
		    
            calc_buoyancy_tend_w_4th_g<<<gridGPU, blockGPU>>>(
                &fields->wt->data_g[offs], &fields->sp["b"]->data_g[offs],
                cosalpha,
                grid->istart,  grid->jstart, grid->kstart+1,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error(); 
		    
            calc_buoyancy_tend_b_4th_g<<<gridGPU, blockGPU>>>(
                &fields->st["b"]->data_g[offs],
                &fields->u->data_g[offs], &fields->w->data_g[offs],
                grid->utrans, n2, sinalpha, cosalpha,
                grid->istart,  grid->jstart, grid->kstart,
                grid->iend,    grid->jend,   grid->kend,
                grid->icellsp, grid->ijcellsp);
            cuda_check_error();
        }
        else
        {
	        calc_buoyancy_tend_4th_g<<<gridGPU, blockGPU>>>(
            &fields->wt->data_g[offs], &fields->sp["b"]->data_g[offs], 
            grid->istart,  grid->jstart, grid->kstart+1,
            grid->iend,    grid->jend,   grid->kend,
            grid->icellsp, grid->ijcellsp);
            cuda_check_error();
        }
    }
}
#endif
