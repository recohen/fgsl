module mod_nlfit
  use, intrinsic :: iso_c_binding
  use fgsl
  use mod_unit
  implicit none
  type data 
     integer(fgsl_size_t) :: n
     real(fgsl_double), allocatable :: y(:), sigma(:)
  end type data
contains
  function expb_f(x, cdata, f) bind(c)
    type(c_ptr), value :: x, cdata, f
    integer(c_int) :: expb_f
!
    type(fgsl_vector) :: f_x, f_f
    type(data), pointer :: f_data
    integer(fgsl_size_t) :: i
    integer(fgsl_int) :: status
    real(fgsl_double) :: yy
    real(fgsl_double), pointer :: p_x(:), p_f(:)
!
    call fgsl_obj_c_ptr(f_x, x)
    call fgsl_obj_c_ptr(f_f, f)
    status = fgsl_vector_align(p_x, f_x)
    status = fgsl_vector_align(p_f, f_f)
    call c_f_pointer(cdata, f_data)
    do i=1,f_data%n
       yy = p_x(1) * exp(- p_x(2) * dble(i-1) ) + p_x(3)
       p_f(i) = (yy - f_data%y(i))/f_data%sigma(i)
    end do
    expb_f = fgsl_success
  end function expb_f
  function expb_df(x, cdata, j) bind(c)
    type(c_ptr), value :: x, cdata, j
    integer(c_int) :: expb_df
!
    type(fgsl_vector) :: f_x
    type(fgsl_matrix) :: f_j
    type(data), pointer :: f_data
    integer(fgsl_size_t) :: i
    integer(fgsl_int) :: status
    real(fgsl_double) :: yy
    real(fgsl_double), pointer :: p_x(:), p_j(:,:)
!
    call fgsl_obj_c_ptr(f_x, x)
    call fgsl_obj_c_ptr(f_j, j)
    status = fgsl_vector_align(p_x, f_x)
    status = fgsl_matrix_align(p_j, f_j)
    call c_f_pointer(cdata, f_data)
    do i=1,f_data%n
       yy = exp(- p_x(2) * dble(i-1) )
       p_j(1,i) = yy / f_data%sigma(i)
       p_j(2,i) = - dble(i-1) * p_x(1) * yy / f_data%sigma(i)
       p_j(3,i) = 1 / f_data%sigma(i)
    end do
    expb_df = fgsl_success
  end function expb_df
  function expb_fdf(x, cdata, f, j) bind(c)
    type(c_ptr), value :: x, cdata, f, j
    integer(c_int) :: expb_fdf
!
    integer(c_int) :: status
    status = expb_f(x, cdata, f)
    status = expb_df(x, cdata, j)
    expb_fdf = fgsl_success
  end function expb_fdf
end module mod_nlfit
program nlfit
  use mod_nlfit
  implicit none
  integer(fgsl_size_t), parameter :: nmax = 10
  integer(fgsl_int), parameter :: itmax_root = 50
  real(fgsl_double), parameter :: eps6 = 1.0d-6
  integer(fgsl_size_t) :: nrt
  integer(fgsl_int) :: i, status
  real(fgsl_double) :: xv(3)
  type(c_ptr) :: ptr
  type(fgsl_rng) :: rng
!  type(fgsl_nlfit_params_t) :: nlfit_params
  type(fgsl_multifit_function_fdf) :: nlfit_fdf
  type(fgsl_multifit_fdfsolver) :: nlfit_slv
  type(fgsl_vector) :: xvec
  type(data), target :: fitdata
!
! Test simulated annealing routines
!
  call unit_init(20)
!
  rng = fgsl_rng_alloc(fgsl_rng_default)
  fitdata%n = nmax
  allocate(fitdata%y(nmax),fitdata%sigma(nmax))
  do i=1, nmax
     fitdata%y(i) = 1.0_fgsl_double + 5.0_fgsl_double * exp(-0.1_fgsl_double*dble(i-1)) + &
          fgsl_ran_gaussian(rng, 0.1_fgsl_double)
     fitdata%sigma(i) = 0.1_fgsl_double
  end do
  ptr = c_loc(fitdata)
  nrt = 3_fgsl_size_t
  nlfit_fdf = fgsl_multifit_function_fdf_init(expb_f, expb_df, expb_fdf, nmax, nrt, ptr)
  nlfit_slv = fgsl_multifit_fdfsolver_alloc(fgsl_multifit_fdfsolver_lmsder, nmax, nrt)
  xv(1:3) = (/1.0_fgsl_double, 0.0_fgsl_double, 0.0_fgsl_double/)
  xvec = fgsl_vector_init(1.0_fgsl_double)
  status = fgsl_vector_align(xv,nrt,xvec,nrt,0_fgsl_size_t,1_fgsl_size_t)
  call unit_assert_true('fgsl_multifit_fdfsolver_alloc', &
       fgsl_well_defined(nlfit_slv), .true.)

  status = fgsl_multifit_fdfsolver_set(nlfit_slv, nlfit_fdf, xvec)
  call unit_assert_equal('fgsl_multifit_fdfsolver_set:status', &
       fgsl_success,status)
  i = 0
  do
     i = i + 1
     status = fgsl_multifit_fdfsolver_iterate(nlfit_slv)
     if (status /= fgsl_success .or. i > itmax_root) then
        exit
     end if
     status = fgsl_multifit_test_delta(fgsl_multifit_fdfsolver_dx(nlfit_slv), &
          fgsl_multifit_fdfsolver_position(nlfit_slv), eps6, eps6)
     if (status == fgsl_success) then 
        exit
     end if
  end do
  call unit_assert_equal('fgsl_multifit_fdfsolver_iterate:status', &
       fgsl_success,status)
! FIXME: result check
  call fgsl_vector_free(xvec)
  call fgsl_multifit_fdfsolver_free(nlfit_slv)
  call fgsl_multifit_function_fdf_free(nlfit_fdf)
  deallocate(fitdata%y,fitdata%sigma)
  call fgsl_rng_free(rng)
!
! Done
!
  call unit_finalize() 
end program nlfit
