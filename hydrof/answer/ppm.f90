module ppm
  use mpi
  implicit none

  private :: color
  public :: outputppm, outputppm_mpiio

contains

pure function color(val, lo, hi) result(rgb)
  implicit none
  character, dimension(3) :: rgb
  real, intent(IN) :: val, lo, hi

  real :: scaleval 
  integer :: tmp

  scaleval = (val-lo)/(hi-lo) * 255.
  tmp = scaleval*3
  if (tmp > 255) tmp = 255
  rgb(1) = achar(tmp)
  rgb(2) = achar(int(scaleval))
  rgb(3) = achar(0)
end function color

subroutine outputppm(var,filename,varnum)
  use solver, only : nguard
  implicit none
  character(len=*), intent(IN), optional :: filename
  integer, intent(IN), optional :: varnum
  real, dimension(:,:,:), intent(IN) :: var
  character, dimension(:,:,:), allocatable :: rgb
  real :: lo, hi
  real :: globlo, globhi
  integer :: c, i,j
  integer :: nx, ny, nvars
  character(len=30) :: chosenfilename
  integer :: chosenvarnum
  integer :: ierr

  if (present(varnum)) then
      chosenvarnum = varnum
  else
      chosenvarnum = 1
  endif
  if (present(filename)) then
      chosenfilename = filename
  else
      chosenfilename = 'output.ppm'
  endif

  nvars = size(var,1)
  nx = size(var,2)
  ny = size(var,3)

  if (chosenvarnum > nvars) then
      print *, 'Invalid variable number ', chosenvarnum
  else
      allocate(rgb(3,nx,ny))

      lo = minval(var(chosenvarnum,:,:))
      call MPI_Allreduce(lo, globlo, 1, MPI_REAL, MPI_MIN, MPI_COMM_WORLD, ierr)
      hi = maxval(var(chosenvarnum,:,:))
      call MPI_Allreduce(hi, globhi, 1, MPI_REAL, MPI_MAX, MPI_COMM_WORLD, ierr)

      forall (i=1:nx, j=1:ny)
          rgb(1:3,i,j) = color(var(chosenvarnum,i,j), globlo, globhi)
      end forall
  
      open(unit=44,file=chosenfilename)
      write(44,'(A)') 'P6'
      write(44,'(2(1x,i4))') nx, ny
      write(44,'(i3)'), 255
      write(44,'(9999999A1)',advance='no') (((rgb(c,i,j),c=1,3), i=1,nx),j=ny,1,-1)
      close(44)

      deallocate(rgb)
  endif
end subroutine outputppm


subroutine outputppm_mpiio(var,n,start,filename,varnum)
  use solver, only : nguard
  implicit none
  character(len=*), intent(IN), optional :: filename
  integer, intent(IN) :: n, start
  integer, intent(IN), optional :: varnum
  real, dimension(:,:,:), intent(IN) :: var
  character, dimension(:,:,:), allocatable :: rgb
  real :: lo, hi
  real :: globlo, globhi
  integer :: i,j
  integer :: nx, ny, nvars
  character(len=30) :: chosenfilename
  integer :: chosenvarnum
  integer :: fileregion 
  integer :: rank
  integer :: ierr
  integer :: fh
  integer(MPI_OFFSET_KIND) :: offset
  integer, dimension(MPI_STATUS_SIZE) :: rstatus

  if (present(varnum)) then
      chosenvarnum = varnum
  else
      chosenvarnum = 1
  endif
  if (present(filename)) then
      chosenfilename = filename
  else
      chosenfilename = 'output.ppm'
  endif

  nvars = size(var,1)
  nx = size(var,2)
  ny = size(var,3)

  call MPI_Type_create_subarray(2, [3*n,n], [3*(nx-2*nguard), n], [3*(start-1), 0], &
                                MPI_ORDER_FORTRAN, MPI_CHARACTER, fileregion, ierr)
  call MPI_Type_commit(fileregion, ierr)

  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)

  if (chosenvarnum > nvars) then
      print *, 'Invalid variable number ', chosenvarnum
  else
      allocate(rgb(3,nx-2*nguard,ny-2*nguard))

      lo = minval(var(chosenvarnum,:,:))
      call MPI_Allreduce(lo, globlo, 1, MPI_REAL, MPI_MIN, MPI_COMM_WORLD, ierr)
      hi = maxval(var(chosenvarnum,:,:))
      call MPI_Allreduce(hi, globhi, 1, MPI_REAL, MPI_MAX, MPI_COMM_WORLD, ierr)

      forall (i=1:nx-2*nguard, j=1:ny-2*nguard)
          rgb(1:3,i,j) = color(var(chosenvarnum,i+nguard,j+nguard), globlo, globhi)
      end forall
  
      if (rank == 0) then 
          open(unit=44,file=chosenfilename)
          write(44,'(A)') 'P6'
          write(44,'(2(1x,i4))') n, n
          write(44,'(i3)'), 255
          close(44)
      endif 
      call MPI_File_open(MPI_COMM_WORLD, chosenfilename, ior(MPI_MODE_WRONLY, MPI_MODE_APPEND), &
                         MPI_INFO_NULL, fh, ierr)
      offset = 18
      call MPI_File_set_view(fh, offset, MPI_CHARACTER, fileregion, "native", MPI_INFO_NULL, ierr)
      call MPI_File_write_all(fh, rgb, 3*(nx-2*nguard)*(ny-2*nguard), MPI_CHARACTER, rstatus, ierr)
      call MPI_File_close(fh, ierr)
      deallocate(rgb)
  endif
end subroutine outputppm_mpiio

end module ppm
